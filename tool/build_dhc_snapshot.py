"""Build the bundled Delhi High Court snapshot from public eCourts metadata.

Source: AWS Open Data "Indian High Court Judgments"
(s3://indian-high-court-judgments, CC BY 4.0), the same metadata the
Open India Law corpus (Vaquill AI, CC BY 4.0) is built on.

Usage:
    python tool/build_dhc_snapshot.py dhc2023.parquet dhc2024.parquet dhc2025.parquet \
        --out assets/data/dhc_snapshot.json

Download the inputs (no credentials needed):
    https://indian-high-court-judgments.s3.amazonaws.com/metadata/parquet/year=YYYY/court=7_26/bench=dhcdb/metadata.parquet

Nothing here is invented. Counsel names are parsed from the first ~290
characters of each judgment header, so they can be incomplete; the app labels
them as parsed and unverified, and never derives outcomes from this data.
"""

import argparse
import datetime as dt
import json
import re
import sys

import pandas as pd

HONORIFIC = r"(?:Mr|Ms|Mrs|Dr|Sh|Shri|Smt|Mx)\.?\s*"
NAME = r"([A-Z][A-Za-z'\-]*(?:\s*\.?\s*[A-Z][A-Za-z'\-]*){0,5})"
COUNSEL_RE = re.compile(HONORIFIC + NAME)
STOP_AFTER = re.compile(
    r"\b(versus|vs\.?|CORAM|\.{3,}\s*Respondents?|\.{3,}\s*Appellants?|\.{3,}\s*Petitioners?)\b",
    re.I,
)
GOVT_ROLE = re.compile(
    r"\b(APP|ASC|SPP|CGSC|GP|ASG|SSC|Standing Counsel|Addl\.?|Additional|Public Prosecutor|Govt)\b",
    re.I,
)
SENIOR = re.compile(r"\bSr\.?\s*Adv|\bSenior Adv", re.I)
TITLE_RE = re.compile(r"^(?P<type>.+?)/(?P<num>[\d\-]+)/(?P<yr>\d{4})\s+of\s+(?P<rest>.*)$")


def clean_name(raw: str) -> str | None:
    name = re.sub(r"\s+", " ", raw.replace(".", ". ")).strip(" .,")
    name = re.sub(r"\s+(Adv|Advs|Advocate|Advocates|Sr|APP|ASC|SPP|CGSC|Counsel|for|with|and|the|State)$", "", name, flags=re.I)
    parts = [p for p in name.split(" ") if p]
    if not parts or len(name) < 4 or len(parts) > 6:
        return None
    if parts[0].lower() in {"justice", "counsel", "none", "appearance"}:
        return None
    out = []
    for p in parts:
        if len(p.rstrip(".")) == 1:
            out.append(p.rstrip(".").upper() + ".")
        else:
            out.append(p[:1].upper() + p[1:].lower())
    return " ".join(out)


def parse_counsel(desc: str):
    """Return [(name, side, role)] with side 'p' (petitioner/appellant) or 'r'."""
    result = []
    if not desc:
        return result
    chunks = re.split(r"Through\s*:?", desc)
    for i, chunk in enumerate(chunks[1:3]):
        side = "p" if i == 0 else "r"
        stop = STOP_AFTER.search(chunk)
        truncated = stop is None
        seg = chunk[: stop.start()] if stop else chunk
        matches = list(COUNSEL_RE.finditer(seg))
        if truncated and matches:
            matches = matches[:-1]  # the last name may be cut off mid-word
        for m in matches:
            name = clean_name(m.group(1))
            if not name:
                continue
            tail = seg[m.end(): m.end() + 60]
            role = "sr" if SENIOR.search(tail[:20]) else ("gov" if GOVT_ROLE.search(tail[:40]) else "adv")
            result.append((name, side, role))
    return result


PRESENT_SEG = re.compile(
    r"\bfor\s+(?:the\s+)?(?:(?P<p>petitioners?|appellants?|applicants?|plaintiffs?|revisionists?)|"
    r"(?P<r>respondents?|state|caveators?|defendants?|r-?\d|u\.?o\.?i|union of india|non-applicants?))[^.;]*[.;]?",
    re.I,
)
PRESENT_GOV = re.compile(
    r"Advocate General|\bA\.?A\.?G\b|\bD\.?A\.?G\b|Addl\.?|Additional|Deputy|Asstt\.?|Assistant|State Counsel|"
    r"Public Prosecutor|\bP\.?P\b|Panel Counsel|Central Govt|\bCGSC\b|\bASG\b|Standing Counsel", re.I)


def parse_present(text: str):
    """Counsel from a "Present:" block (Punjab and Haryana and similar courts)."""
    m = re.search(r"Present\s*[:\-]+", text or "")
    if not m:
        return []
    block = text[m.end():]
    stop = re.search(r"\n\s*1\.\s|\*{3,}\s*\n?\s*[A-Z .]+,\s*J\.|\bJ\.\s*\((?:Oral)\)|\n\s*O\s*R\s*D\s*E\s*R|\n\s*J\s*U\s*D\s*G", block)
    block = re.sub(r"\s+", " ", block[: stop.start()] if stop else block[:1500])
    out = []
    pos = 0
    segs = []
    for sm in PRESENT_SEG.finditer(block):
        segs.append((block[pos: sm.end()], "p" if sm.group("p") else "r"))
        pos = sm.end()
    tail = block[pos:]
    if tail.strip():
        segs.append((tail, None))
    for seg, side in segs:
        for cm in COUNSEL_RE.finditer(seg):
            name = clean_name(cm.group(1))
            if not name:
                continue
            after = seg[cm.end(): cm.end() + 60]
            gov = bool(PRESENT_GOV.search(after[:45]))
            sr = bool(SENIOR.search(after[:25]))
            sd = side or ("r" if gov else None)
            if sd is None:
                continue  # side not stated: leave it out rather than guess
            out.append((name, sd, "sr" if sr else ("gov" if gov else "adv")))
    return out


def judge_names(raw: str):
    if not raw:
        return []
    names = []
    for part in re.split(r",\s*(?=HON|MR|MS|MRS|DR|THE)", raw):
        chief = "CHIEF JUSTICE" in part.upper() and "ACTING" not in part.upper()
        acting = "ACTING CHIEF JUSTICE" in part.upper()
        n = re.sub(r"(HON'?BLE\s+)?(THE\s+)?(MR\.?|MS\.?|MRS\.?|DR\.?)?\s*(ACTING\s+)?(CHIEF\s+)?JUSTICE\s*", "", part, flags=re.I)
        n = clean_name(n.strip())
        if not n and chief:
            names.append("The Chief Justice")
            continue
        if not n or "Pertaining" in n or "Bench" in n:
            continue
        prefix = "Acting Chief Justice " if acting else ("Chief Justice " if chief else "Justice ")
        names.append(prefix + n)
    return names


def doc_type(desc: str) -> str:
    d = re.sub(r"\s+", "", (desc or "").upper())
    if "JUDGMENT" in d:
        return "j"
    if "ORDER" in d:
        return "o"
    return "u"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("--out", required=True)
    ap.add_argument("--court-id", default="dhc")
    ap.add_argument("--court-name", default="High Court of Delhi")
    ap.add_argument("--court-path", default="court=7_26/bench=dhcdb")
    ap.add_argument("--title-prefix", default="", help="keep only case types starting with this, e.g. CWP")
    ap.add_argument("--title-contains", default="", help="keep only titles containing this (case-insensitive)")
    args = ap.parse_args()

    frames = []
    for p in args.inputs:
        f = pd.read_parquet(p)
        f["src_year"] = int(re.search(r"(\d{4})", p.rsplit("/", 1)[-1]).group(1))
        frames.append(f)
    df = pd.concat(frames, ignore_index=True)
    df = df.dropna(subset=["cnr", "title", "decision_date"])
    df = df.sort_values("decision_date", ascending=False)
    # One record per CNR + decision date (the dedup key the app uses too).
    df["date"] = df["decision_date"].dt.strftime("%Y-%m-%d")
    df = df.drop_duplicates(subset=["cnr", "date"])
    if args.title_prefix:
        df = df[df["title"].str.startswith(args.title_prefix, na=False)]
    if args.title_contains:
        df = df[df["title"].str.contains(args.title_contains, case=False, na=False)]

    judges, judge_ix = [], {}
    counsel, counsel_ix = [], {}
    cases = []
    types, type_ix = [], {}
    skipped = 0
    for row in df.itertuples(index=False):
        m = TITLE_RE.match(row.title.strip())
        if not m:
            skipped += 1
            continue
        rest = m.group("rest")
        pet, _, res = rest.partition(" Vs ")
        jids = []
        for j in judge_names(row.judge):
            if j not in judge_ix:
                judge_ix[j] = len(judges)
                judges.append(j)
            jids.append(judge_ix[j])
        cids = []
        seen = set()
        desc = row.description or ""
        parsed = parse_counsel(desc) if "Through" in desc else parse_present(desc)
        for name, side, role in parsed:
            key = re.sub(r"[^a-z]", "", name.lower())
            if key not in counsel_ix:
                counsel_ix[key] = len(counsel)
                counsel.append(name)
            k = (counsel_ix[key], side)
            if k in seen:
                continue
            seen.add(k)
            cids.append([counsel_ix[key], side, role])
        pdf = (row.pdf_link or "").rsplit("/", 1)[-1]
        if pdf == f"{row.cnr}_1_{row.date}.pdf":
            pdf = ""  # the app derives the default file name
        ctype = m.group("type").strip()
        if ctype not in type_ix:
            type_ix[ctype] = len(types)
            types.append(ctype)
        cases.append([
            row.cnr,
            type_ix[ctype],
            m.group("num"),
            int(m.group("yr")),
            pet.strip().title()[:140],
            res.strip().title()[:140],
            row.date,
            jids,
            cids,
            pdf,
            doc_type(row.description),
            int(row.src_year),
        ])

    years = sorted({c[6][:4] for c in cases})
    snapshot = {
        "meta": {
            "court_id": args.court_id,
            "scope": " ".join(x for x in [args.title_prefix and f"{args.title_prefix} cases", args.title_contains and f"naming {args.title_contains.title()}"] if x) or "all cases",
            "court": args.court_name,
            "source": "eCourts judgments portal metadata via AWS Open Data: Indian High Court Judgments",
            "source_url": "https://registry.opendata.aws/indian-high-court-judgments/",
            "pdf_base": "https://indian-high-court-judgments.s3.amazonaws.com/data/pdf/",
            "pdf_path": "year={src_year}/" + args.court_path + "/{file}",
            "pdf_default": "{cnr}_1_{date}.pdf",
            "licence": "CC BY 4.0",
            "attribution": "Judgment metadata from the eCourts judgments portal, via the Indian High Court Judgments dataset on AWS Open Data (CC BY 4.0). Corpus structure follows Open India Law by Vaquill AI (CC BY 4.0).",
            "years": years,
            "built": dt.date.today().isoformat(),
            "count": len(cases),
            "columns": ["cnr", "case_type", "case_no", "reg_year", "petitioner", "respondent", "date", "judges", "counsel", "pdf", "doc", "src_year"],
        },
        "case_types": types,
        "judges": judges,
        "counsel": counsel,
        "cases": cases,
    }
    # Index file (meta + lookup tables) plus one case file per decision year,
    # so no single asset exceeds web hosting limits.
    base = args.out.rsplit(".json", 1)[0]
    parts = []
    for y in years:
        part = [c for c in cases if c[6][:4] == y]
        name = f"{base.rsplit('/', 1)[-1]}_{y}.json"
        with open(f"{base}_{y}.json", "w") as f:
            json.dump(part, f, separators=(",", ":"), ensure_ascii=False)
        parts.append(name)
    snapshot["meta"]["parts"] = parts
    del snapshot["cases"]
    with open(args.out, "w") as f:
        json.dump(snapshot, f, separators=(",", ":"), ensure_ascii=False)
    print(f"cases={len(cases)} skipped={skipped} judges={len(judges)} counsel={len(counsel)}", file=sys.stderr)


if __name__ == "__main__":
    main()
