"""Pools candidate judgments per gold-set question with today's keyword search.

Each question runs as itself and as each of its keyword queries; the lists are
fused by reciprocal rank and the top N are kept for the lawyer to grade.
Usage: python tool/eval/pool_candidates.py <knowledge.db> <questions.json> <out.json>
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "server"))
from rag import KnowledgeLayer  # noqa: E402

N = 8
db, qpath, out = sys.argv[1:4]
kl = KnowledgeLayer(db)
qs = json.load(open(qpath))
res = []
for i, q in enumerate(qs, 1):
    if q["route"] == "aggregate":
        res.append({"n": i, "candidates": []})
        continue
    side = {"petitioner": "p", "respondent": "r"}.get(q["side"])
    queries = [q["q"]] + q["kw"] if q["route"] != "lookup" else q["kw"]
    rrf, keep = {}, {}
    for text in queries:
        hits = kl.retrieve(kl.interpret(" ".join([text, q.get("statutes", "")]), side), k=60)
        for rank, h in enumerate(hits):
            rrf[h.record_id] = rrf.get(h.record_id, 0) + 1 / (60 + rank)
            keep.setdefault(h.record_id, h)
    top = sorted(rrf, key=rrf.get, reverse=True)[:N]
    cands = []
    for rid in top:
        m = keep[rid].meta
        cands.append({"id": rid, "case_number": m["case_number"], "title": f"{m['petitioner']} v. {m['respondent']}",
                      "date": m["decision_date"], "outcome": m["outcome"], "case_type": m["case_type"],
                      "pdf_url": m["pdf_url"], "passage": " ".join((keep[rid].passage or "").split())[:300]})
    res.append({"n": i, "candidates": cands})
    print(i, q["route"], len(cands), cands[0]["title"][:70] if cands else "-", flush=True)
json.dump(res, open(out, "w"), indent=1)
