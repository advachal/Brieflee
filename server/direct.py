"""Answers that come straight from the database, with no model: lookups of a
named case and counts of outcomes.

Lookups find a case by its number ("CS(COMM) 412/2022") or by party names
("GM Modular v. Syska"). Counts tally the outcomes Brieflee read from the
operative sentence, by year, for the decisions that match the subject and Act
named in the question. Both say exactly what they matched, so a lawyer can
check the rule as well as the number.
"""
import json
import re
from collections import Counter, defaultdict

from rag import KnowledgeLayer, Retrieved
from subjects import detect

OUTCOME_LABEL = {"petitioner": "allowed (petitioner won)", "respondent": "dismissed (respondent won)",
                 "partly": "partly allowed", "settled": "settled", "withdrawn": "withdrawn", "consent": "by consent",
                 "infructuous": "infructuous", "interim": "interim order", "appointed": "arbitrator appointed",
                 "unknown": "outcome not read"}
DECIDED = ("petitioner", "respondent", "partly")

# Words in a question → how the Act is written in the records' statutes list.
ACTS = [
    (r"\bndps\b|narcotic", ("NDPS", "Narcotic")),
    (r"arbitra|section 34\b|s\.\s?34\b|section 37\b|section 9\b", ("Arbitration",)),
    (r"trade ?mark", ("Trade Mark",)),
    (r"\bpatent(?! illegality)", ("Patents Act",)),
    (r"copyright", ("Copyright",)),
    (r"income ?tax|reassessment|section 148", ("Income Tax", "Income-tax", "Income-Tax")),
    (r"\bgst\b|cgst", ("Goods and Services Tax", "CGST", "GST")),
    (r"rent control|eviction|leave to defend", ("Rent Control",)),
    (r"negotiable instruments|cheque|section 138", ("Negotiable Instruments", "NI Act")),
    (r"money laundering|pmla", ("Money Laundering", "PMLA")),
]
SECTION = re.compile(r"\b(?:section|sec\.?|s\.)\s*(\d+[A-Z]?)\b", re.I)
YEAR = re.compile(r"\b((?:19|20)\d{2})\b")


def _norm(s: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", (s or "").upper())


def _hit(kl: KnowledgeLayer, m: dict, passage: str | None = None) -> Retrieved:
    if passage is None:
        row = kl.db.execute("SELECT text FROM chunks WHERE record_id = ? ORDER BY chunk_index LIMIT 1", (m["id"],)).fetchone()
        t = " ".join((row["text"] if row else "").split())
        passage = t[:320] + (" …" if len(t) > 320 else "")
    return Retrieved(m["id"], 1.0, passage, dict(m))


# Lookup --------------------------------------------------------------------
def by_case_number(kl: KnowledgeLayer, case_type: str, number: str, year: str) -> list[Retrieved]:
    rows = kl.db.execute("SELECT * FROM records WHERE case_number LIKE ?", (f"%{number}/{year}",)).fetchall()
    want = _norm(case_type)
    exact = [r for r in rows if _norm(r["case_number"]) == want + _norm(f"{number}/{year}")]
    loose = [r for r in rows if r not in exact and _norm(r["case_type"])[:3] == want[:3]]
    out = sorted(exact, key=lambda r: r["decision_date"] or "", reverse=True) + loose[:5]
    return [_hit(kl, dict(r)) for r in out[:20]]


_SKIP = {"M/S", "MS", "THE", "AND", "ANR", "ORS", "LTD", "LIMITED", "PVT", "PRIVATE", "CO", "OF", "INDIA", "&"}


def _tokens(name: str) -> list[str]:
    return [t for t in re.findall(r"[A-Z0-9]+", name.upper()) if t not in _SKIP and len(t) > 1]


def by_parties(kl: KnowledgeLayer, a: str, b: str = "", limit: int = 20) -> list[Retrieved]:
    ta, tb = _tokens(a), _tokens(b)
    if not ta:
        return []
    key = max(ta, key=len)
    rows = kl.db.execute("SELECT * FROM records WHERE petitioner LIKE ? OR respondent LIKE ?", (f"%{key}%", f"%{key}%")).fetchall()

    def has(text, toks):
        t = set(re.findall(r"[A-Z0-9]+", (text or "").upper()))
        return all(x in t for x in toks)

    out = []
    for r in rows:
        p, q = r["petitioner"], r["respondent"]
        if tb:
            ok = (has(p, ta) and has(q, tb)) or (has(p, tb) and has(q, ta))
        else:
            ok = has(p, ta) or has(q, ta)
        if ok:
            out.append(r)
    out.sort(key=lambda r: r["decision_date"] or "", reverse=True)
    return [_hit(kl, dict(r)) for r in out[:limit]]


# Counts --------------------------------------------------------------------
def count(kl: KnowledgeLayer, question: str) -> dict:
    """Outcomes by year for the decisions matching the question's subject, Act and section."""
    q = question.lower()
    subjects = detect(question)
    acts = [names for rx, names in ACTS if re.search(rx, q)]
    sections = sorted({s.upper() for s in SECTION.findall(question)})
    years = sorted({int(y) for y in YEAR.findall(question)})
    lo, hi = (years[0], years[-1]) if years else (2015, 2025)
    if re.search(r"\bsince\b", q) and years:
        hi = 2025
    if not acts and not subjects:
        return {"ok": False, "reason": "No subject or Act recognised in the question, so nothing to count."}
    rows = kl.db.execute(
        "SELECT id, case_type, decision_date, outcome, acts, court FROM records WHERE substr(decision_date, 1, 4) BETWEEN ? AND ?",
        (str(lo), str(hi))).fetchall()
    by_year: dict[str, Counter] = defaultdict(Counter)
    matched = []
    for r in rows:
        a = json.loads(r["acts"] or "[]")
        if acts and not all(any(any(n.lower() in x.lower() for n in names) for x in a) for names in acts):
            continue
        if sections and not any(x.startswith(f"s.{s} ") for s in sections for x in a):
            continue
        if not acts and subjects and not any(f(r["case_type"] or "") for _, _, f in subjects):
            continue
        by_year[r["decision_date"][:4]][r["outcome"]] += 1
        matched.append(r["id"])
    table = []
    for y in sorted(by_year):
        c = by_year[y]
        decided = sum(c[o] for o in DECIDED)
        table.append({"year": y, "total": sum(c.values()), "decided": decided, "allowed": c["petitioner"],
                      "partly": c["partly"], "dismissed": c["respondent"],
                      "share_allowed": round((c["petitioner"] + c["partly"]) / decided, 3) if decided else None,
                      "other": {OUTCOME_LABEL.get(k, k): v for k, v in c.items() if k not in DECIDED}})
    rule = []
    if acts:
        rule.append("the judgment names " + " and ".join("/".join(n) for n in acts))
    if sections:
        rule.append("cites section " + ", ".join(sections) + " of it")
    if not acts and subjects:
        rule.append("case type is " + ", ".join(l for _, l, _ in subjects))
    return {"ok": True, "years": [lo, hi], "rule": "Decisions where " + "; ".join(rule) + f", decided {lo} to {hi}.",
            "note": "Allowed and dismissed come from the operative sentence. Settled, withdrawn, interim and unread "
                    "outcomes are listed apart and not counted as decided.",
            "by_year": table, "matched": len(matched), "sample_ids": matched[:20], "_ids": matched}


def count_answer(c: dict) -> str:
    if not c.get("ok"):
        return c.get("reason", "Nothing to count.")
    lines = [c["rule"]]
    for r in c["by_year"]:
        share = f", {round(100 * r['share_allowed'])}% allowed or partly allowed" if r["share_allowed"] is not None else ""
        lines.append(f"{r['year']}: {r['total']} decisions, {r['decided']} with a clear result "
                     f"({r['allowed']} allowed, {r['partly']} partly, {r['dismissed']} dismissed{share}).")
    lines.append(c["note"])
    return "\n".join(lines)


def top_counsel(kl: KnowledgeLayer, record_ids: list[str], side: str | None = None, limit: int = 15) -> list[dict]:
    """Advocates appearing most often in a set of decisions (government panels included, marked)."""
    tally: Counter = Counter()
    roles: dict[int, Counter] = defaultdict(Counter)
    for i in range(0, len(record_ids), 500):
        b = record_ids[i:i + 500]
        q = f"SELECT counsel_id, side, role FROM appearances WHERE record_id IN ({','.join('?' * len(b))})"
        for a in kl.db.execute(q, b):
            if side and a["side"] != side:
                continue
            tally[a["counsel_id"]] += 1
            roles[a["counsel_id"]][a["role"] or "private"] += 1
    return [{"counsel_id": cid, "name": kl.counsel.get(cid, "?"), "appearances": n, "roles": dict(roles[cid])}
            for cid, n in tally.most_common(limit)]
