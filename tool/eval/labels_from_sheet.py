"""Turns the lawyer's labelling sheet into goldset/labels.json.

Export the Questions and Candidates sheets as CSV (the page's download menu),
then:
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


def rows(path):
    with open(path, newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def main(qcsv, ccsv, db=None):
    cands = {c["n"]: c["candidates"] for c in json.load(open(os.path.join(HERE, "goldset", "candidates.json")))}
    labels: dict[str, dict] = {}
    for r in rows(ccsv):
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
        import direct
        import router
        from rag import KnowledgeLayer
        kl = KnowledgeLayer(db)
    for r in rows(qcsv):
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
        lab["counsel"] = [x.strip() for x in re.split(r"[;\n]", counsel) if x.strip()]
        for item in [x.strip() for x in re.split(r"[;\n]", missing) if x.strip()]:
            found = []
            if kl:
                rt = router.route(item if " v" in item.lower() or "/" in item else f"show {item}")
                if "case_number" in rt:
                    found = direct.by_case_number(kl, *rt["case_number"])[:1]
                elif "parties" in rt:
                    found = direct.by_parties(kl, *rt["parties"])[:1]
            if found:
                lab["missing"].append(found[0].record_id)
            else:
                lab["missing_text"].append(item)
    out = os.path.join(HERE, "goldset", "labels.json")
    json.dump(labels, open(out, "w"), indent=1, ensure_ascii=False)
    graded = sum(1 for v in labels.values() if v["grades"])
    print(f"{len(labels)} questions with labels ({graded} graded) -> {out}")


if __name__ == "__main__":
    main(*sys.argv[1:4])
