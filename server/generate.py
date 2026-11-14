"""Optional grounded answer generation with an LLM (Gemini or Claude, see llm.py).

Only runs when an LLM key is configured. The model sees the
retrieved passages and the computed counsel statistics and may only use
those; every claim must cite a record id in [brackets]. With no credentials
the service returns a deterministic template answer instead.
"""
SYSTEM = (
    "You answer questions about Delhi High Court case law for a counsel-discovery product. "
    "Use ONLY the decisions and statistics provided. Cite every factual statement with the record id in square "
    "brackets, e.g. [DLHC010123452024_2025-03-04]. Never invent cases, outcomes, counsel or numbers. "
    "Counsel statistics come from appearances parsed from judgment headers and outcomes read from operative "
    "sentences; say so briefly. Do not call anyone the 'best' lawyer: describe the evidence. If the evidence is "
    "thin, say that plainly. Keep the answer under 220 words, in plain English."
)


import llm


def available() -> bool:
    return llm.available()


def grounded_answer(question: str, cases: list[dict], counsel: list[dict]) -> str | None:
    if not available():
        return None
    lines = ["DECISIONS:"]
    for c in cases[:12]:
        lines.append(
            f"[{c['id']}] {c['case_number']} | {c['title']} | {c['decision_date']} | bench: {', '.join(c['judges'])} | "
            f"outcome: {c['outcome']} | operative sentence: {c['outcome_evidence'] or 'n/a'} | passage: {c['passage']}")
    lines.append("\nCOUNSEL (computed from the decisions above and other similar decisions):")
    for r in counsel[:8]:
        lines.append(
            f"{r['name']}: {r['similar_matters']} similar matters, {r['favourable']} favourable / {r['unfavourable']} "
            f"unfavourable eligible outcomes, sufficient evidence: {r['sufficient_evidence']}, "
            f"favourable in: {', '.join(r['evidence']['favourable'][:5])}")
    try:
        return llm.complete(SYSTEM, "\n".join(lines) + f"\n\nQUESTION: {question}")
    except Exception:
        return None
