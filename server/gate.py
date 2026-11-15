"""The answer gate: checks a generated answer against what was retrieved
before anyone sees it.

1. Citations: every [record id] in the answer must be one of the decisions
   given to the model. An id it made up, or remembered from elsewhere, fails.
2. Quotes: every passage in quotation marks (25 characters or more) must
   appear, after normalising spaces and punctuation, in the text of a decision
   the answer cites, or of any decision given to the model.
3. Grounding: an answer with no citation at all fails.
4. Evidence: fewer than MIN_STRONG decisions rated 2 or 3 by the re-ranker (or
   fewer than MIN_STRONG decisions found, when there was no re-ranking) does
   not fail the answer, but it is marked thin and the answer says so.

A failed answer is replaced by a short notice that says why; the decisions
and counsel evidence are still shown. This module has no I/O: the caller passes the texts.
"""
import re

MIN_STRONG = 3
CITE = re.compile(r"\[([A-Za-z0-9_\-]{8,})\]")
QUOTE = re.compile(r"[\"“]([^\"”]{25,600})[\"”]")
WITHHELD = ("The AI summary was withheld because it failed the source check ({why}). "
            "The decisions and counsel evidence below come straight from the records.")
THIN_NOTE = "The evidence is thin: only {n} closely matching decision{s} found, so treat this as a starting point."


def _flat(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", (s or "").lower()).strip()


def check(answer: str | None, case_ids: list[str], texts: dict[str, str], ratings: dict[str, dict] | None = None,
          found: int | None = None) -> dict:
    """texts: {record_id: full or partial text} for the decisions given to the model."""
    allowed = set(case_ids)
    if ratings:
        strong = sum(1 for r in ratings.values() if (r.get("relevance") or 0) >= 2)
    else:
        strong = found if found is not None else len(case_ids)
    result = {"passed": True, "problems": [], "cited": [], "unknown_citations": [], "unmatched_quotes": [],
              "strong_matches": strong, "thin_evidence": strong < MIN_STRONG}
    if not answer:
        return result
    cited = list(dict.fromkeys(CITE.findall(answer)))
    result["cited"] = cited
    unknown = [c for c in cited if c not in allowed]
    if unknown:
        result["unknown_citations"] = unknown
        result["problems"].append(f"cites {len(unknown)} decision(s) that were not retrieved")
    if not cited:
        result["problems"].append("cites no decision")
    pool = [texts.get(c, "") for c in cited if c in allowed] or list(texts.values())
    flat_pool = [_flat(t) for t in pool]
    for q in QUOTE.findall(answer):
        fq = _flat(q)
        if fq and not any(fq in t for t in flat_pool):
            result["unmatched_quotes"].append(q[:120])
    if result["unmatched_quotes"]:
        result["problems"].append(f"{len(result['unmatched_quotes'])} quotation(s) not found in the cited decisions")
    result["passed"] = not result["problems"]
    return result


def apply(answer: str | None, result: dict) -> tuple[str | None, str]:
    """Returns (answer to show, answer_kind)."""
    if not answer:
        return None, "none"
    if not result["passed"]:
        return WITHHELD.format(why="; ".join(result["problems"])), "withheld_by_gate"
    if result["thin_evidence"]:
        n = result["strong_matches"]
        return THIN_NOTE.format(n=n, s=" was" if n == 1 else "s were") + "\n\n" + answer, "generated_grounded_thin"
    return answer, "generated_grounded"
