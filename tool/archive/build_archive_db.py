"""Build the server knowledge database from the harvested archive text.

Inputs (all downloaded by the build workflow):
  shards/text_<year>_<court>_<bench>.jsonl.gz    judgment text (harvest_tar.py)
  meta/hc_<year>_<court>_<bench>.parquet          AWS Open Data metadata, High Court
  meta/sc_<year>.parquet                          AWS Open Data metadata, Supreme Court

Output: a SQLite database with the schema server/rag.py reads (source,
records, counsel, appearances, chunks, chunks_fts), plus a `court` column.
Record ids for the Delhi High Court are "<CNR>_<YYYY-MM-DD>", the same ids the
app uses, so links between the app and the server line up.

Outcomes: Delhi High Court from the operative sentence (outcomes.py, with the
sentence kept as evidence); Supreme Court from the court's own "disposal
nature" field, checked against the operative sentence when it is vague.
Counsel: Delhi from the judgment header ("Through:" / "Represented by:");
Supreme Court from the law-report line "<names> for the Appellant."

    python tool/archive/build_archive_db.py --shards shards --meta meta --db knowledge.db
"""
import argparse
import collections
import glob
import gzip
import json
import math
import os
import re
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "knowledge"))
sys.path.insert(0, os.path.join(HERE, ".."))
from outcomes import extract_outcome  # noqa: E402
from build_knowledge import ACT, SECTION, canon_act, chunks, clean_text, header_counsel, tokens  # noqa: E402

HC_PDF = "https://indian-high-court-judgments.s3.amazonaws.com/data/pdf/year={y}/court={c}/bench={b}/{f}"
SC_PDF = "https://indian-supreme-court-judgments.s3.amazonaws.com/data/pdf/year={y}/english/{f}"
COURT_NAMES = {"7_26": "Delhi High Court", "sc": "Supreme Court of India"}

HC_TITLE = re.compile(r"^(?P<type>.+?)/(?P<num>[\d\-]+)/(?P<yr>\d{4})\s+of\s+(?P<rest>.*)$")
JUDGE_PREFIX = re.compile(r"HON'?\s*BLE\s+(?:THE\s+)?(?:(?:ACTING\s+)?CHIEF\s+)?(?:MR\.?|MS\.?|MRS\.?|DR\.?)?\s*(?:JUSTICE\s+)?", re.I)
SC_CASE_NO = re.compile(r"Case No :</span><font[^>]*>\s*([^<]+)<", re.I)
SC_CORAM = re.compile(r"Coram :\s*(.*?)</strong>", re.I | re.S)
SC_FOR = re.compile(r"\bfor\s+the\s+(Appellants?|Petitioners?|Respondents?|Applicants?|Interveners?|State|Complainant)\b")
SC_GOV = re.compile(r"\b(A\.?S\.?G|S\.?G\b|Solicitor General|Attorney General|A\.?A\.?G|Advocate General|Standing Counsel)", re.I)


def judge_names(raw: str) -> list[str]:
    out = []
    for part in re.split(r",|\band\b", raw or ""):
        n = JUDGE_PREFIX.sub("", part).strip(" .*")
        n = re.sub(r"<[^>]+>", "", n).strip()
        if len(n) > 3:
            out.append("Justice " + " ".join(w[:1] + w[1:].lower() if len(w) > 2 else w for w in n.split()))
    return out


def norm_key(name: str) -> str:
    return re.sub(r"[^a-z]", "", name.lower())


def title_case(n: str) -> str:
    n = re.sub(r"\s+", " ", n).strip(" ,.;")
    return " ".join(p if (len(p.rstrip(".")) <= 2 and p.isupper()) else p[:1].upper() + p[1:].lower() for p in n.split(" "))


def sc_counsel(text: str) -> list[tuple[str, str, str]]:
    """Counsel from the law-report line '<A>, <B> and <C> for the Appellant.'"""
    flat = re.sub(r"\s+", " ", text[:40000])
    flat = re.sub(r"\s[A-H]\s(?=[A-Z])", " ", flat)  # margin letters of the printed report
    out, seen = [], set()
    last = 0
    for m in SC_FOR.finditer(flat):
        side = "r" if m.group(1).lower().startswith(("respondent", "state", "complainant")) else "p"
        seg = flat[max(last, m.start() - 700): m.start()]
        last = m.end()
        # the names follow the previous sentence ("... in RP No. 365 of 2014. Pawanshree Agrawal and ...")
        cut = [x.end() for x in re.finditer(r"([A-Za-z]+|\d+\)?)\.\s", seg) if len(x.group(1)) > 1 and x.group(1) not in ("Sr", "Mr", "Ms", "Mrs", "No", "Dr", "Adv", "Advs", "Nos")]
        if cut:
            seg = seg[cut[-1]:]
        for raw in re.split(r",|\band\b|;", seg):
            raw = raw.strip()
            role = "sr" if re.search(r"Sr\.?\s*Adv", raw) else ("gov" if SC_GOV.search(raw) else "adv")
            raw = re.sub(r"\b(Sr|Advs?|Adv|ASG|AAG|SG)\.?$", "", raw).strip(" .")
            words = raw.split()
            if not (2 <= len(words) <= 6) or any(w.lower() in {"for", "the", "of", "from", "in", "dated", "high", "court", "no", "order", "judgment"} for w in words):
                continue
            if not all(w[:1].isupper() for w in words):
                continue
            name = title_case(raw)
            k = (norm_key(name), side)
            if len(norm_key(name)) >= 5 and k not in seen:
                seen.add(k)
                out.append((name, side, role))
        if len(out) > 60:
            break
    return out


SC_DISPOSAL = [
    (re.compile(r"partly|partially|in part", re.I), "partly"),
    (re.compile(r"\ballowed\b|accepted|set aside|quashed", re.I), "petitioner"),
    (re.compile(r"dismissed|rejected", re.I), "respondent"),
    (re.compile(r"withdrawn", re.I), "withdrawn"),
    (re.compile(r"infructuous", re.I), "infructuous"),
    (re.compile(r"settle|compromise", re.I), "settled"),
]


def sc_outcome(disposal: str, text: str) -> tuple[str, str]:
    for rx, outcome in SC_DISPOSAL:
        if disposal and rx.search(disposal):
            return outcome, f"Disposal recorded by the Supreme Court: {disposal.strip()}"
    return extract_outcome(text)


def load_meta(meta_dir: str) -> dict[str, dict]:
    import pandas as pd

    meta: dict[str, dict] = {}
    for p in glob.glob(os.path.join(meta_dir, "hc_*.parquet")):
        _, year, c1, c2, bench = os.path.basename(p)[:-8].split("_", 4)
        court = f"{c1}_{c2}"
        for r in pd.read_parquet(p, columns=["title", "judge", "pdf_link", "cnr", "decision_date", "disposal_nature"]).itertuples():
            f = os.path.basename(str(r.pdf_link or ""))
            if not f:
                continue
            t = HC_TITLE.match(str(r.title or ""))
            pet, _, res = (t.group("rest") if t else str(r.title or "")).partition(" Vs ")
            meta[f"{court}/{f}"] = {
                "court": court, "bench": bench, "year": int(year), "cnr": r.cnr,
                "case_type": t.group("type").strip() if t else "", "case_number": f"{t.group('type').strip()} {t.group('num')}/{t.group('yr')}" if t else str(r.title or "")[:80],
                "petitioner": pet.strip(), "respondent": res.strip(), "judges": judge_names(str(r.judge or "")),
                "date": str(r.decision_date)[:10], "disposal": str(r.disposal_nature or ""),
                "pdf": HC_PDF.format(y=year, c=court, b=bench, f=f),
            }
    for p in glob.glob(os.path.join(meta_dir, "sc_*.parquet")):
        year = os.path.basename(p)[3:7]
        for r in pd.read_parquet(p).itertuples():
            f = f"{r.path}_EN.pdf"
            html = str(r.raw_html or "")
            cn = SC_CASE_NO.search(html)
            coram = SC_CORAM.search(html)
            d = str(r.decision_date or "")
            date = f"{d[6:10]}-{d[3:5]}-{d[0:2]}" if re.match(r"\d\d-\d\d-\d{4}", d) else d[:10]
            case_number = re.sub(r"\s+", " ", cn.group(1)).strip() if cn else str(r.case_id or "")
            meta[f"sc/{f}"] = {
                "court": "sc", "bench": "english", "year": int(year), "cnr": r.cnr,
                "case_type": re.sub(r"\s*No\.?.*$", "", case_number, flags=re.I).strip().upper(), "case_number": case_number,
                "petitioner": str(r.petitioner or ""), "respondent": str(r.respondent or ""),
                "judges": judge_names(coram.group(1) if coram else str(r.judge or "")),
                "date": date, "disposal": str(r.disposal_nature or ""), "citation": str(r.citation or ""),
                "pdf": SC_PDF.format(y=year, f=f),
            }
    return meta


def record_id(m: dict, f: str) -> str:
    if m["court"] == "sc":
        return f"SC_{f[:-7]}"
    parts = f[:-4].split("_")
    return f"{parts[0]}_{parts[-1]}" if len(parts) >= 3 else f[:-4]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shards", required=True)
    ap.add_argument("--meta", required=True)
    ap.add_argument("--db", required=True)
    a = ap.parse_args()
    meta = load_meta(a.meta)
    print(f"metadata rows: {len(meta)}", file=sys.stderr, flush=True)
    shards = sorted(glob.glob(os.path.join(a.shards, "*.jsonl.gz")))

    def docs():
        for s in shards:
            for line in gzip.open(s, "rt", encoding="utf-8"):
                d = json.loads(line)
                if not d.get("text") or len(d["text"].strip()) < 200:
                    continue
                m = meta.get(f"{d['court']}/{d['file']}")
                if m is None:
                    continue
                yield d, m

    # Pass 1: document frequencies for key terms.
    df: collections.Counter = collections.Counter()
    n_docs = 0
    for d, _ in docs():
        df.update(set(tokens(d["text"][:60000])))
        n_docs += 1
    print(f"documents with text and metadata: {n_docs}", file=sys.stderr, flush=True)
    rare_floor = 2

    if os.path.exists(a.db):
        os.remove(a.db)
    db = sqlite3.connect(a.db)
    db.executescript("""
    PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF;
    CREATE TABLE source(key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE records(id TEXT PRIMARY KEY, cnr TEXT, case_type TEXT, case_number TEXT, petitioner TEXT,
        respondent TEXT, decision_date TEXT, judges TEXT, outcome TEXT, outcome_evidence TEXT, pages INT,
        pdf_url TEXT, acts TEXT, key_terms TEXT, court TEXT);
    CREATE TABLE counsel(id INTEGER PRIMARY KEY, name TEXT);
    CREATE TABLE appearances(record_id TEXT, counsel_id INT, side TEXT, role TEXT, source TEXT);
    CREATE TABLE chunks(rowid INTEGER PRIMARY KEY, record_id TEXT, chunk_index INT, text TEXT);
    CREATE VIRTUAL TABLE chunks_fts USING fts5(text, content='chunks', content_rowid='rowid', tokenize='porter');
    """)
    counsel_ix: dict[str, int] = {}
    counsel_names: list[str] = []
    outcomes: collections.Counter = collections.Counter()
    per_court: collections.Counter = collections.Counter()
    rowid = 0
    seen_ids = set()
    for i, (d, m) in enumerate(docs()):
        rid = record_id(m, d["file"])
        if rid in seen_ids:
            continue
        seen_ids.add(rid)
        text = d["text"]
        clean = clean_text(text)
        if m["court"] == "sc":
            outcome, evidence = sc_outcome(m["disposal"], text)
            found = sc_counsel(text)
        else:
            outcome, evidence = extract_outcome(text)
            found = header_counsel(re.sub(r"Represented\s+by\s*:?", "Through:", text[:8000])) or []
        outcomes[outcome] += 1
        per_court[m["court"]] += 1
        tf = collections.Counter(tokens(clean[:60000]))
        terms = [w for _, w in sorted(((c * math.log(n_docs / (1 + df[w])), w) for w, c in tf.items() if df[w] >= rare_floor), reverse=True)[:30]]
        flat = re.sub(r"\s+", " ", clean)
        acts = collections.Counter(x for x in (canon_act(f"{x.group(1)} {x.group(2)}") for x in ACT.finditer(flat)) if x)
        secs = collections.Counter(f"s.{x.group(1)} {act}" for x in SECTION.finditer(flat) if (act := canon_act(x.group(2))))
        statutes = [x for x, _ in acts.most_common(4)] + [x for x, _ in secs.most_common(6)]
        db.execute("INSERT INTO records VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (
            rid, m["cnr"], m["case_type"], m["case_number"], m["petitioner"], m["respondent"], m["date"],
            json.dumps(m["judges"]), outcome, evidence, d.get("pages", 0), m["pdf"], json.dumps(statutes),
            json.dumps(terms), m["court"]))
        seen_c = set()
        for name, side, role in found:
            if m["court"] != "sc" and re.search(r"\b(Mr|Ms|Mrs|Dr)\b|\.\s*[A-Z][a-z]+\.", name):
                continue
            key = norm_key(name)
            if len(key) < 5:
                continue
            if key not in counsel_ix:
                counsel_ix[key] = len(counsel_names)
                counsel_names.append(name)
            k = (counsel_ix[key], side)
            if k not in seen_c:
                seen_c.add(k)
                db.execute("INSERT INTO appearances VALUES (?,?,?,?,?)", (rid, counsel_ix[key], side, role,
                                                                           "law_report" if m["court"] == "sc" else "pdf_header"))
        for j, ch in enumerate(chunks(clean)):
            rowid += 1
            db.execute("INSERT INTO chunks VALUES (?,?,?,?)", (rowid, rid, j, ch))
        if i % 10000 == 0:
            db.commit()
            print(f"{i} records, {rowid} chunks", file=sys.stderr, flush=True)
    db.executemany("INSERT INTO counsel VALUES (?,?)", list(enumerate(counsel_names)))
    print("indexing", file=sys.stderr, flush=True)
    db.executescript("""
    CREATE INDEX ix_app_counsel ON appearances(counsel_id);
    CREATE INDEX ix_app_record ON appearances(record_id);
    CREATE INDEX ix_chunks_record ON chunks(record_id);
    CREATE INDEX ix_records_court ON records(court);
    INSERT INTO chunks_fts(chunks_fts) VALUES('rebuild');
    """)
    source = {
        "name": "Delhi High Court and Supreme Court of India judgments, 2015 to 2025",
        "attribution": "Judgments from the eCourts and Supreme Court of India portals via the AWS Open Data Registry "
                       "(indian-high-court-judgments, indian-supreme-court-judgments; CC BY 4.0), as indexed by Open India Law.",
        "records": len(seen_ids), "courts": {COURT_NAMES.get(c, c): n for c, n in per_court.items()},
        "outcome_counts": dict(outcomes), "counsel": len(counsel_names),
    }
    db.executemany("INSERT INTO source VALUES (?,?)", [(k, json.dumps(v)) for k, v in source.items()])
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(json.dumps(source, indent=1), file=sys.stderr)


if __name__ == "__main__":
    main()
