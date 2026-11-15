"""Scores Brieflee against the gold set, one stage at a time, so a drop can be
traced to the stage that caused it.

    python tool/eval/run_eval.py --db knowledge.db                 # search alone, no AI (free, repeatable)
    python tool/eval/run_eval.py --url https://…onrender.com        # the live service: understanding + re-ranking

Stages and metrics:
  route      share of questions the router sends where the gold set says
  retrieval  recall@10, recall@30, MRR (relevant = graded 2 or 3, or added by
             the lawyer as missing), nDCG@10 on the 0-3 grades, and how many
             of the top 10 were never graded (a high number means the gold set
             needs more labels before the score can be trusted)
  answers    with --url: share of answers that passed the answer gate, and why
             the others failed
  outcomes   share of checked outcomes the lawyer marked correct

Writes tool/eval/results/<date>-<mode>.json and prints a summary table.
"""
import argparse
import json
import math
import os
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "server"))
import router  # noqa: E402

SEARCH_ROUTES = ("simple", "complex", "lookup")


def load(name, default=None):
    p = os.path.join(HERE, "goldset", name)
    return json.load(open(p)) if os.path.exists(p) else default


def relevant(lab: dict) -> set[str]:
    return {rid for rid, g in lab.get("grades", {}).items() if g >= 2} | set(lab.get("missing", []))


def metrics(ranked: list[str], lab: dict) -> dict:
    rel = relevant(lab)
    grades = {**{m: 3 for m in lab.get("missing", [])}, **lab.get("grades", {})}
    out = {"relevant": len(rel)}
    if not rel:
        return out
    out["recall@10"] = len(rel & set(ranked[:10])) / len(rel)
    out["recall@30"] = len(rel & set(ranked[:30])) / len(rel)
    first = next((i for i, r in enumerate(ranked) if r in rel), None)
    out["mrr"] = 0.0 if first is None else 1 / (first + 1)
    dcg = sum((2 ** grades.get(r, 0) - 1) / math.log2(i + 2) for i, r in enumerate(ranked[:10]))
    ideal = sorted(grades.values(), reverse=True)[:10]
    idcg = sum((2 ** g - 1) / math.log2(i + 2) for i, g in enumerate(ideal))
    out["ndcg@10"] = dcg / idcg if idcg else 0.0
    out["unjudged@10"] = sum(1 for r in ranked[:10] if r not in grades)
    return out


def run_local(db: str):
    import direct
    from rag import KnowledgeLayer
    kl = KnowledgeLayer(db)

    def ask(q: str) -> tuple[list[str], dict]:
        r = router.route(q)
        if r["route"] == "lookup":
            hits = direct.by_case_number(kl, *r["case_number"]) if "case_number" in r else direct.by_parties(kl, *r["parties"])
            if hits:
                return [h.record_id for h in hits], {}
        hits = kl.retrieve(kl.interpret(q), k=60)
        return [h.record_id for h in hits], {}
    return ask


def run_service(url: str):
    def ask(q: str) -> tuple[list[str], dict]:
        req = urllib.request.Request(url.rstrip("/") + "/v1/ask", data=json.dumps({"question": q, "limit": 30}).encode(),
                                     headers={"Content-Type": "application/json"})
        for attempt in range(3):
            try:
                with urllib.request.urlopen(req, timeout=300) as r:
                    d = json.load(r)
                return [c["id"] for c in d.get("cases", [])], d
            except urllib.error.HTTPError as e:
                if e.code == 429:
                    time.sleep(61)
                    continue
                raise
        return [], {}
    return ask


def mean(xs):
    xs = [x for x in xs if x is not None]
    return round(sum(xs) / len(xs), 3) if xs else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db")
    ap.add_argument("--url")
    ap.add_argument("--only-labelled", action="store_true", default=True)
    a = ap.parse_args()
    qs = load("questions.json")
    labels = load("labels.json", {})
    report = {"date": time.strftime("%Y-%m-%d"), "mode": "service" if a.url else "search-only", "questions": []}

    route_ok = [router.route(x["q"])["route"] == x["route"] for x in qs]
    report["route_accuracy"] = round(sum(route_ok) / len(qs), 3)

    ask = run_service(a.url) if a.url else (run_local(a.db) if a.db else None)
    if ask is None:
        print(f"route accuracy {report['route_accuracy']} ({sum(route_ok)}/{len(qs)}); give --db or --url to score retrieval")
        return
    for n, x in enumerate(qs, 1):
        lab = labels.get(str(n))
        if x["route"] not in SEARCH_ROUTES or (a.only_labelled and not (lab and relevant(lab))):
            continue
        t = time.time()
        ranked, resp = ask(x["q"])
        row = {"n": n, "route": x["route"], "area": x["area"], "seconds": round(time.time() - t, 1), **metrics(ranked, lab)}
        if resp:
            g = resp.get("gate") or {}
            row.update(answer_kind=resp.get("answer_kind"), gate_passed=g.get("passed"), gate_problems=g.get("problems"))
        report["questions"].append(row)
        print(n, {k: (round(v, 2) if isinstance(v, float) else v) for k, v in row.items() if k not in ("n", "area")}, flush=True)

    rows = report["questions"]
    summary = {k: mean([r.get(k) for r in rows]) for k in ("recall@10", "recall@30", "mrr", "ndcg@10", "unjudged@10")}
    summary["questions_scored"] = len(rows)
    by_route = {}
    for rt in SEARCH_ROUTES:
        rr = [r for r in rows if r["route"] == rt]
        if rr:
            by_route[rt] = {"n": len(rr), "recall@10": mean([r.get("recall@10") for r in rr]), "mrr": mean([r.get("mrr") for r in rr])}
    summary["by_route"] = by_route
    gated = [r for r in rows if r.get("gate_passed") is not None]
    if gated:
        summary["gate_pass_rate"] = mean([1.0 if r["gate_passed"] else 0.0 for r in gated])
    checks = [c["answer"] for lab in labels.values() for c in lab.get("outcome_checks", {}).values() if c["answer"] in ("Yes", "No")]
    if checks:
        summary["outcome_accuracy"] = round(checks.count("Yes") / len(checks), 3)
        summary["outcomes_checked"] = len(checks)
    report["summary"] = summary
    os.makedirs(os.path.join(HERE, "results"), exist_ok=True)
    out = os.path.join(HERE, "results", f"{report['date']}-{report['mode']}.json")
    json.dump(report, open(out, "w"), indent=1)
    print("\nroute accuracy", report["route_accuracy"])
    for k, v in summary.items():
        print(f"{k:>18}: {v}")
    print("->", out)


if __name__ == "__main__":
    main()
