"""The AI steps around retrieval: understand the request first, then check
that what was found really fits it.

1. understand(question): reads a natural-language question and returns what
   the person needs (a one-line reading, their side, the statutes, and 2 to 4
   search queries: one plain-language description of the situation for the
   search by meaning, and keyword queries with the terms a matching judgment
   would contain).
2. rerank(context, hits): the model reads the top candidate decisions
   (title, case type, statutes, the matching passage) against the request and
   scores each 0 to 3 with a one-line reason. Decisions it judges unrelated
   move down; the counsel evidence is then weighed by this relevance.
Both steps are skipped (and the plain hybrid search is used) when no model is
configured or the model call fails.
"""
import json

import llm
from rag import KnowledgeLayer, Retrieved

UNDERSTAND_SCHEMA = {
    "type": "object",
    "properties": {
        "reading": {"type": "string"},
        "client_side": {"type": "string", "enum": ["petitioner", "respondent", "unclear"]},
        "statutes": {"type": "array", "items": {"type": "string"}},
        "meaning_query": {"type": "string"},
        "keyword_queries": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["reading", "client_side", "statutes", "meaning_query", "keyword_queries"],
    "additionalProperties": False,
}

UNDERSTAND_SYSTEM = (
    "You turn a question from an Indian lawyer or litigant into searches over Delhi High Court and Supreme Court "
    "judgments, to find decided matters like theirs and the counsel who appeared. "
    "reading: one plain sentence saying what they need. client_side: the side they act for or want counsel for "
    "(petitioner/plaintiff/appellant, respondent/defendant), 'unclear' if not evident. statutes: the provisions "
    "involved, written 's.<number> <Act name, year>' or the Act name; include ones clearly implied (e.g. a "
    "challenge to an arbitral award is s.34 Arbitration and Conciliation Act, 1996). meaning_query: two or three "
    "sentences describing the facts and legal question the way a judgment would state them. keyword_queries: 2 "
    "or 3 short queries of the exact legal terms such a judgment would contain. Do not answer the question."
)

RERANK_SCHEMA = {
    "type": "object",
    "properties": {
        "ratings": {"type": "array", "items": {
            "type": "object",
            "properties": {"n": {"type": "integer"}, "relevance": {"type": "integer"}, "why": {"type": "string"}},
            "required": ["n", "relevance", "why"], "additionalProperties": False}},
    },
    "required": ["ratings"],
    "additionalProperties": False,
}

RERANK_SYSTEM = (
    "You check search results for a lawyer. For each numbered decision, judge how closely it matches the "
    "MATTER: 3 = same kind of dispute and same legal question, 2 = same legal question in a different setting, "
    "1 = same area of law only, 0 = unrelated (a word matched by chance). Use only the text given. why: at most "
    "15 words naming what matches or what differs. Rate every decision."
)

RERANK_TOP = 30


def understand(question: str) -> dict | None:
    if not llm.available():
        return None
    try:
        u = llm.complete_json(UNDERSTAND_SYSTEM, f"QUESTION: {question}", UNDERSTAND_SCHEMA, fast=True)
    except Exception:
        return None
    if not u or not (u.get("meaning_query") or u.get("keyword_queries")):
        return None
    return u


def search(kl: KnowledgeLayer, queries: list[str], side: str | None, statutes: list[str] | None = None,
           per_query: int = 120) -> list[Retrieved]:
    """Runs each query (hybrid keywords + meaning) and fuses the lists by rank."""
    fused: dict[str, Retrieved] = {}
    rrf: dict[str, float] = {}
    for q in [q for q in queries if q and q.strip()]:
        interp = kl.interpret(" ".join([q, *(statutes or [])]), side)
        for rank, h in enumerate(kl.retrieve(interp, k=per_query)):
            rrf[h.record_id] = rrf.get(h.record_id, 0.0) + 1.0 / (60 + rank)
            fused.setdefault(h.record_id, h)
    order = sorted(rrf, key=rrf.get, reverse=True)
    return [Retrieved(r, rrf[r] * 1000, fused[r].passage, fused[r].meta) for r in order]


def rerank(context: str, hits: list[Retrieved]) -> tuple[list[Retrieved], dict[str, dict]]:
    """Reorders the top candidates by the model's relevance rating. Returns the
    hits and {record_id: {"relevance": 0-3, "why": str}} (empty when skipped)."""
    if not llm.available() or not hits:
        return hits, {}
    top = hits[:RERANK_TOP]
    lines = []
    for n, h in enumerate(top, 1):
        m = h.meta
        acts = ", ".join(json.loads(m.get("acts") or "[]")[:4])
        lines.append(f"{n}. {m.get('petitioner')} v. {m.get('respondent')} | {m.get('case_type') or ''} "
                     f"{m.get('case_number') or ''} | {m.get('decision_date') or ''} | statutes: {acts or 'n/a'}\n"
                     f"   passage: {' '.join((h.passage or '').split())[:420]}")
    try:
        out = llm.complete_json(RERANK_SYSTEM, f"MATTER:\n{context[:3000]}\n\nDECISIONS:\n" + "\n".join(lines),
                                RERANK_SCHEMA, fast=True)
    except Exception:
        return hits, {}
    ratings = {}
    for r in (out or {}).get("ratings") or []:
        try:
            n = int(r.get("n"))
            rel = max(0, min(3, int(r.get("relevance"))))
        except (TypeError, ValueError):
            continue
        if 1 <= n <= len(top):
            ratings[top[n - 1].record_id] = {"relevance": rel, "why": (r.get("why") or "").strip()}
    if len(ratings) < len(top) // 2:  # the model skipped most of them: keep the search order
        return hits, {}
    first = top[0].score or 1.0
    rated = []
    for i, h in enumerate(top):
        rel = ratings.get(h.record_id, {}).get("relevance", 1)
        # Relevance first, search order second; score stays positive so counsel
        # evidence is weighed by it (unrelated decisions count for little).
        rated.append((rel, -i, Retrieved(h.record_id, first * (0.1 + rel) / 3.1, h.passage, h.meta)))
    rated.sort(key=lambda t: (t[0], t[1]), reverse=True)
    rest_scale = (first * 0.1 / 3.1) / (hits[RERANK_TOP].score or 1.0) if len(hits) > RERANK_TOP else 1.0
    rest = [Retrieved(h.record_id, h.score * rest_scale, h.passage, h.meta) for h in hits[RERANK_TOP:]]
    return [t[2] for t in rated] + rest, ratings
