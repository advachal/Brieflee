"""Optional grounded answer generation with Claude.

Only runs when Anthropic credentials are configured. The model sees the
retrieved passages and the computed counsel statistics and may only use
those; every claim must cite a record id in [brackets]. With no credentials
the service returns a deterministic template answer instead.
"""
import os

SYSTEM = (
    "You answer questions about Delhi High Court case law for a counsel-discovery product. "
    "Use ONLY the decisions and statistics provided. Cite every factual statement with the record id in square "
    "brackets, e.g. [DLHC010123452024_2025-03-04]. Never invent cases, outcomes, counsel or numbers. "
    "Counsel statistics come from appearances parsed from judgment headers and outcomes read from operative "
    "sentences; say so briefly. Do not call anyone the 'best' lawyer: describe the evidence. If the evidence is "
    "thin, say that plainly. Keep the answer under 220 words, in plain English."
)


def available() -> bool:
    return bool(os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("ANTHROPIC_AUTH_TOKEN"))


def grounded_answer(question: str, cases: list[dict], counsel: list[dict]) -> str | None:
    if not available():
        return None
    import anthropic

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
    client = anthropic.Anthropic()
    response = client.beta.messages.create(
        model="claude-opus-5-5",
        max_tokens=16000,
        output_config={"effort": "medium"},
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
        system=SYSTEM,
        messages=[{"role": "user", "content": "\n".join(lines) + f"\n\nQUESTION: {question}"}],
    )
    if response.stop_reason == "refusal":
        return None
    return "".join(b.text for b in response.content if b.type == "text").strip() or None
