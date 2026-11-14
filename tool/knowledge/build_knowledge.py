"""Build the Brieflee knowledge layer from harvested judgment texts.

Inputs
  assets/data/dhc_snapshot*.json      record metadata (case, bench, CNR, PDF)
  build/knowledge/texts.jsonl         text extracted from the official PDFs

Outputs
  build/knowledge/knowledge.db        SQLite: records, counsel, appearances,
                                      outcomes with evidence, text chunks and
                                      an FTS5 (BM25) index over the chunks.
                                      Used by the RAG server in server/.
  assets/data/dhc_knowledge.json      compact layer bundled in the app:
                                      per record outcome + evidence sentence,
                                      key terms, statutes and full counsel list.

Nothing is generated: outcomes come from the operative sentence of the order
(see outcomes.py) and are stored with that sentence as evidence.
"""
import argparse, collections, json, math, os, re, sqlite3, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from outcomes import extract_outcome  # noqa: E402
from build_dhc_snapshot import parse_counsel, parse_present, clean_name  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(ROOT, "assets", "data")

STOP = set("""a about above after again against all also am an and any are as at be because been before being below
between both but by can could did do does doing down during each few for from further had has have having he her here
hers him his how i if in into is it its itself just me more most my no nor not now of off on once only or other our out
over own same she should so some such than that the their them then there these they this those through to too under
until up very was we were what when where which while who whom why will with you your shall may must said thus hence
therefore however whereas herein thereof hereby wherein upon within without would also vide dated date learned counsel
court hon ble honble justice mr ms mrs sh shri smt dr j petitioner petitioners respondent respondents appellant
appellants plaintiff plaintiffs defendant defendants applicant applicants advocate advocates adv advs sr senior para
paragraph present instant order orders judgment judgments case cases matter matters filed submitted submits submission
submissions stated states view facts fact made make one two three four five first second third delhi high new
appl appln cm ia no nos ors anr ltd pvt private limited vs versus mat aforesaid above-mentioned noted note page
behalf appearing appear appears issue issued notice therein thereafter accordingly pending application applications
disposed list listed hearing heard sought seeks seeking relief reliefs prayer prayed per even well like""".split())
TOKEN = re.compile(r"[a-z][a-z\-]{2,}")
ACT = re.compile(r"\b((?:[A-Z][A-Za-z&]+\s(?:(?:and|of|the|for|&)\s)?){1,8}Act),?\s*(\d{4})")
SECTION = re.compile(r"\bSections?\s+(\d+[A-Z]?)(?:\s*\(\d+\))?(?:\s*\([a-z]\))?\s+of\s+the\s+((?:[A-Z][A-Za-z&]+\s(?:(?:and|of|the|for|&)\s)?){1,8}Act)")
FOOTER = re.compile(
    r"(Digitally )?Signed By\s*:?.{0,60}?Signing Date\s*:?\s*[\d.]+\s*[\d:]*|Signature Not Verified"
    r"|Click here to check corrigendum, if any|Page \d+ of \d+|This is a digitally signed order.*?QR code shown above\.?"
    r"|The Order is downloaded from the DHC Server on [\d/]+ at [\d:]+", re.I)


_ACT_CANON = [
    (re.compile(r"arbitration|a\s*&\s*c act|conciliation act", re.I), "Arbitration and Conciliation Act, 1996"),
    (re.compile(r"commercial courts", re.I), "Commercial Courts Act, 2015"),
    (re.compile(r"trade ?marks?", re.I), "Trade Marks Act, 1999"),
    (re.compile(r"copyright", re.I), "Copyright Act, 1957"),
    (re.compile(r"patents?", re.I), "Patents Act, 1970"),
    (re.compile(r"designs?", re.I), "Designs Act, 2000"),
    (re.compile(r"contract", re.I), "Indian Contract Act, 1872"),
    (re.compile(r"stamp", re.I), "Indian Stamp Act, 1899"),
    (re.compile(r"companies", re.I), "Companies Act"),
    (re.compile(r"insolvency", re.I), "Insolvency and Bankruptcy Code, 2016"),
    (re.compile(r"limitation", re.I), "Limitation Act, 1963"),
    (re.compile(r"specific relief", re.I), "Specific Relief Act, 1963"),
    (re.compile(r"negotiable", re.I), "Negotiable Instruments Act, 1881"),
    (re.compile(r"msmed|micro, small", re.I), "MSMED Act, 2006"),
]
_ACT_SKIP = re.compile(r"disaster management|amendment act|general clauses", re.I)


def canon_act(name: str):
    name = re.sub(r"\s+", " ", name).strip()
    if _ACT_SKIP.search(name):
        return None
    for rx, canon in _ACT_CANON:
        if rx.search(name):
            return canon
    return name


def clean_text(t: str) -> str:
    t = FOOTER.sub(" ", t)
    return re.sub(r"[ \t]+", " ", t).strip()


def tokens(t: str):
    return [w for w in TOKEN.findall(t.lower()) if w not in STOP]


NAME_TOKENS: set = set()


def chunks(text: str, size: int = 1400, overlap: int = 200):
    paras = re.split(r"\n\s*\n|(?<=\.)\s*\n(?=\d+\.)", text)
    buf = ""
    for p in paras:
        p = re.sub(r"\s+", " ", p).strip()
        if not p:
            continue
        if len(buf) + len(p) + 1 <= size:
            buf = f"{buf} {p}".strip()
            continue
        if buf:
            yield buf
        while len(p) > size:
            yield p[:size]
            p = p[size - overlap:]
        buf = p
    if buf:
        yield buf


def header_counsel(text: str):
    head_raw = text[:6000]
    if "Through" not in head_raw and re.search(r"Present\s*[:\-]", head_raw):
        return parse_present(head_raw)
    flat = re.sub(r"\s+", " ", text[:6000])
    stop = re.search(r"CORAM", flat)
    head = flat[: stop.start() + 5] if stop else flat[:2500]
    return parse_counsel(head)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--texts", default=os.path.join(ROOT, "build/knowledge/texts.jsonl"))
    ap.add_argument("--db", default=os.path.join(ROOT, "build/knowledge/knowledge.db"))
    ap.add_argument("--app-out", default=os.path.join(DATA, "dhc_knowledge.json"))
    ap.add_argument("--snapshot", default=os.path.join(DATA, "dhc_snapshot.json"))
    a = ap.parse_args()

    idx = json.load(open(a.snapshot))
    meta, types, judges = idx["meta"], idx["case_types"], idx["judges"]
    counsel_names = list(idx["counsel"])
    records = {}
    for part in meta["parts"]:
        for r in json.load(open(os.path.join(DATA, part))):
            records[f"{r[0]}_{r[6]}"] = r
    counsel_ix = {re.sub(r"[^a-z]", "", n.lower()): i for i, n in enumerate(counsel_names)}

    docs = []
    for line in open(a.texts):
        d = json.loads(line)
        if d.get("text") and d["id"] in records:
            docs.append(d)
    print(f"documents with text: {len(docs)}", file=sys.stderr)

    # Person names are not subject matter: keep them out of key terms.
    name_tokens = set()
    for n in counsel_names + judges:
        name_tokens.update(w for w in re.findall(r"[a-z]+", n.lower()) if len(w) > 2)

    # Document frequencies for key-term selection.
    df = collections.Counter()
    doc_tokens = {}
    for d in docs:
        d["clean"] = clean_text(d["text"])
        toks = tokens(d["clean"])
        doc_tokens[d["id"]] = toks
        df.update(set(toks))
    n_docs = max(len(docs), 1)

    if os.path.exists(a.db):
        os.remove(a.db)
    db = sqlite3.connect(a.db)
    db.executescript("""
    CREATE TABLE source(key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE records(id TEXT PRIMARY KEY, cnr TEXT, case_type TEXT, case_number TEXT, petitioner TEXT,
        respondent TEXT, decision_date TEXT, judges TEXT, outcome TEXT, outcome_evidence TEXT, pages INT,
        pdf_url TEXT, acts TEXT, key_terms TEXT);
    CREATE TABLE counsel(id INTEGER PRIMARY KEY, name TEXT);
    CREATE TABLE appearances(record_id TEXT, counsel_id INT, side TEXT, role TEXT, source TEXT);
    CREATE TABLE chunks(rowid INTEGER PRIMARY KEY, record_id TEXT, chunk_index INT, text TEXT);
    CREATE VIRTUAL TABLE chunks_fts USING fts5(text, content='chunks', content_rowid='rowid', tokenize='porter');
    CREATE INDEX ix_app_counsel ON appearances(counsel_id);
    CREATE INDEX ix_app_record ON appearances(record_id);
    CREATE INDEX ix_chunks_record ON chunks(record_id);
    """)
    db.executemany("INSERT INTO source VALUES (?,?)", [(k, json.dumps(v)) for k, v in meta.items()])

    app = {}
    outcome_counts = collections.Counter()
    rowid = 0
    for d in docs:
        r = records[d["id"]]
        outcome, evidence = extract_outcome(d["text"])
        outcome_counts[outcome] += 1
        toks = doc_tokens[d["id"]]
        tf = collections.Counter(toks)
        scored = sorted(
            ((c * math.log(n_docs / (1 + df[w])), w) for w, c in tf.items() if df[w] >= 2 and w not in name_tokens),
            reverse=True,
        )
        terms = [w for _, w in scored[:30]]
        flat = re.sub(r"\s+", " ", d["clean"])
        acts = collections.Counter(
            x for x in (canon_act(f"{m.group(1)} {m.group(2)}") for m in ACT.finditer(flat)) if x)
        sections = collections.Counter(
            f"s.{m.group(1)} {act_}" for m in SECTION.finditer(flat) if (act_ := canon_act(m.group(2))))
        act_list = [x for x, _ in acts.most_common(4)]
        sec_list = [x for x, _ in sections.most_common(6)]

        # Counsel: the full header in the PDF beats the 290-char excerpt.
        app_counsel = []
        seen = set()
        for name, side, role in header_counsel(d["text"]) or []:
            if re.search(r"\b(Mr|Ms|Mrs|Dr)\b|\.\s*[A-Z][a-z]+\.", name):
                continue
            key = re.sub(r"[^a-z]", "", name.lower())
            if key not in counsel_ix:
                counsel_ix[key] = len(counsel_names)
                counsel_names.append(name)
            k = (counsel_ix[key], side)
            if k not in seen:
                seen.add(k)
                app_counsel.append([counsel_ix[key], side, role])
        if not app_counsel:
            app_counsel = r[8]

        f = r[9] or meta["pdf_default"].replace("{cnr}", r[0]).replace("{date}", r[6])
        pdf = meta["pdf_base"] + meta["pdf_path"].replace("{src_year}", str(r[11])).replace("{file}", f)
        db.execute("INSERT INTO records VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (
            d["id"], r[0], types[r[1]], f"{types[r[1]]} {r[2]}/{r[3]}", r[4], r[5], r[6],
            json.dumps([judges[j] for j in r[7]]), outcome, evidence, d.get("pages", 0), pdf,
            json.dumps(act_list + sec_list), json.dumps(terms)))
        for cid, side, role in app_counsel:
            db.execute("INSERT INTO appearances VALUES (?,?,?,?,?)", (d["id"], cid, side, role, "pdf_header"))
        for i, ch in enumerate(chunks(d["clean"])):
            rowid += 1
            db.execute("INSERT INTO chunks VALUES (?,?,?,?)", (rowid, d["id"], i, ch))
        app[d["id"]] = [
            {"petitioner": "p", "respondent": "r", "appointed": "a", "consent": "c", "partly": "m", "settled": "s",
             "withdrawn": "w", "infructuous": "i", "interim": "t"}.get(outcome, "u"),
            evidence[:260],
            terms,
            act_list + sec_list,
            app_counsel,
            d.get("pages", 0),
        ]
    db.executemany("INSERT INTO counsel VALUES (?,?)", list(enumerate(counsel_names)))
    db.execute("INSERT INTO chunks_fts(chunks_fts) VALUES('rebuild')")
    db.commit()
    db.close()

    out = {
        "meta": {
            "built_from": "Official Delhi High Court PDFs (eCourts via AWS Open Data, CC BY 4.0)",
            "documents": len(app),
            "outcome_counts": dict(outcome_counts),
            "outcome_method": "rule-based operative-sentence extraction, conservative; only allowed/dismissed are outcome-eligible",
            "outcome_codes": {"p": "petitioner side succeeded", "r": "respondent side succeeded", "a": "arbitrator appointed (not counted)", "c": "allowed by consent or unopposed (not counted)", "m": "partly allowed",
                              "s": "settled", "w": "withdrawn", "i": "infructuous", "t": "interim order", "u": "not determined"},
            "columns": ["outcome", "evidence", "terms", "statutes", "counsel", "pages"],
        },
        "extra_counsel_start": len(idx["counsel"]),
        "extra_counsel": counsel_names[len(idx["counsel"]):],
        "records": app,
    }
    with open(a.app_out, "w") as fh:
        json.dump(out, fh, separators=(",", ":"), ensure_ascii=False)
    print(f"outcomes={dict(outcome_counts)} chunks={rowid} app_bytes={os.path.getsize(a.app_out)}", file=sys.stderr)


if __name__ == "__main__":
    main()
