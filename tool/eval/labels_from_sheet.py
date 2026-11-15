"""Turns the lawyer's labelling sheet into goldset/labels.json.

Give the downloaded workbook (.xlsx), or CSV exports of its Questions and
Candidates sheets:
    python tool/eval/labels_from_sheet.py gold_set.xlsx [knowledge.db]
    python tool/eval/labels_from_sheet.py questions.csv candidates.csv [knowledge.db]

Candidates are matched back to record ids by question number and rank
(goldset/candidates.json). "Missing judgments" are resolved to record ids by
case number or party names when a database is given; unresolved ones are kept
as text so nothing the lawyer wrote is lost.
"""
import csv
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "server"))


def rows(path, sheet=None):
    if path.endswith(".xlsx"):
        import openpyxl
        ws = openpyxl.load_workbook(path, data_only=True, read_only=True)[sheet]
        it = ws.iter_rows(values_only=True)
        head = [str(h) if h is not None else "" for h in next(it)]
        return [{h: ("" if v is None else str(v)) for h, v in zip(head, r)} for r in it]
    with open(path, newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


CASE_NO_IN = re.compile(r"\b([A-Z][A-Z.()\s]{1,30}?)\s*(\d{1,6})\s*/\s*((?:19|20)\d{2})\b")


def resolve(kl, item: str):
    """A judgment the lawyer named, as a record id, or None. A case number must
    match exactly. Party names must match both sides, and when the lawyer gave
    the court (SC, Delhi HC) or a year, the record must agree (year within one,
    since report years and decision dates differ). Ambiguous names resolve to
    nothing rather than to a guess."""
    import direct
    court = "sc" if re.search(r"\bSC\b|Supreme Court", item) else ("7_26" if re.search(r"Delhi HC|Delhi High Court", item) else None)
    years = [int(y) for y in re.findall(r"\b(19\d{2}|20\d{2})\b", re.sub(r"\d{1,6}\s*/\s*(?:19|20)\d{2}", "", item))]

    def fits(h):
        m = h.meta
        if court and m.get("court") != court:
            return False
        if years and not any(abs(int((m.get("decision_date") or "0000")[:4]) - y) <= 1 for y in years):
            return False
        return True

    m = CASE_NO_IN.search(item)
    if m:
        want = direct._norm(m.group(1)) + direct._norm(f"{m.group(2)}/{m.group(3)}")
        hits = [h for h in direct.by_case_number(kl, m.group(1).strip(), m.group(2), m.group(3))
                if direct._norm(h.meta["case_number"]) == want]
        hits = [h for h in hits if fits(h)] if years or court else hits
        if hits:
            return hits[0].record_id
    names = re.split(r"\s*[,(\[]", item)[0]
    p = re.split(r"\s+(?:v\.?|vs\.?|versus)\s+", names, maxsplit=1, flags=re.I)
    if len(p) == 2 and p[0].strip() and p[1].strip():
        hits = [h for h in direct.by_parties(kl, p[0], p[1], limit=50) if fits(h)]
        if len(hits) == 1:
            return hits[0].record_id
    return None


def main(*args):
    if args[0].endswith(".xlsx"):
        qcsv, ccsv, db = (args[0], "Questions"), (args[0], "Candidates"), (args[1] if len(args) > 1 else None)
    else:
        qcsv, ccsv, db = args[0], args[1], (args[2] if len(args) > 2 else None)
    cands = {c["n"]: c["candidates"] for c in json.load(open(os.path.join(HERE, "goldset", "candidates.json")))}
    labels: dict[str, dict] = {}
    for r in rows(*ccsv) if isinstance(ccsv, tuple) else rows(ccsv):
        try:
            n, rank = int(float(r["Q#"])), int(float(r["Rank"]))
        except (KeyError, ValueError):
            continue
        rel = (r.get("Relevance (0-3)") or "").strip()
        ok = (r.get("Outcome correct?") or "").strip()
        c = cands.get(n, [])
        if not (1 <= rank <= len(c)) or (not rel and not ok):
            continue
        rid = c[rank - 1]["id"]
        lab = labels.setdefault(str(n), {"grades": {}, "outcome_checks": {}, "missing": [], "missing_text": [], "counsel": []})
        if rel in ("0", "1", "2", "3"):
            lab["grades"][rid] = int(rel)
        if ok in ("Yes", "No", "Unclear"):
            lab["outcome_checks"][rid] = {"answer": ok, "brieflee": c[rank - 1]["outcome"]}
    kl = None
    if db:
        from rag import KnowledgeLayer
        kl = KnowledgeLayer(db)
    for r in rows(*qcsv) if isinstance(qcsv, tuple) else rows(qcsv):
        try:
            n = int(float(r["#"]))
        except (KeyError, ValueError):
            continue
        missing = (r.get("Missing judgments") or "").strip()
        counsel = (r.get("Acceptable counsel") or "").strip()
        status = (r.get("Status") or "").strip()
        if not (missing or counsel or status == "Done"):
            continue
        lab = labels.setdefault(str(n), {"grades": {}, "outcome_checks": {}, "missing": [], "missing_text": [], "counsel": []})
        lab["status"] = status
        lab["notes"] = (r.get("Lawyer notes") or "").strip()
        if not counsel.lower().startswith("not applicable"):
            lab["counsel"] = [x.strip() for x in re.split(r"[;\n]", counsel) if x.strip()]
        for item in [x.strip() for x in re.split(r"[;\n]", missing) if x.strip()]:
            rid = resolve(kl, item) if kl else None
            if rid and rid not in lab["grades"] and rid not in lab["missing"]:
                lab["missing"].append(rid)
            elif not rid:
                lab["missing_text"].append(item)
    out = os.path.join(HERE, "goldset", "labels.json")
    json.dump(labels, open(out, "w"), indent=1, ensure_ascii=False)
    graded = sum(1 for v in labels.values() if v["grades"])
    found = sum(len(v["missing"]) for v in labels.values())
    unresolved = sum(len(v["missing_text"]) for v in labels.values())
    print(f"{len(labels)} questions with labels ({graded} graded); missing judgments: {found} found in the database, "
          f"{unresolved} not found (often Supreme Court rulings before 2015 or other courts) -> {out}")


if __name__ == "__main__":
    main(*sys.argv[1:])
