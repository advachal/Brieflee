"""Routes a question by what it needs, before any model is called.

  lookup     a named case: a case number ("CS(COMM) 412/2022") or two parties
             ("GM Modular v. Syska"). Answered from the records table directly.
  aggregate  a count or share ("how many s.34 petitions were allowed in 2024").
             Answered by a database count; the model is not needed.
  complex    comparisons, several stages or courts, appeal chains. Today this
             runs the same pipeline as simple, marked as complex, until the
             agent loop exists.
  simple     one matter, one question: understand, search, re-rank, answer.

Rules only; they are cheap and testable. Order matters: a case number is the
strongest signal, then counting words, then comparison words, then "X v. Y".
"""
import re

CASE_NO = re.compile(
    r"\b((?:[A-Z][A-Z]*\.?\s?){1,4}(?:\((?:[A-Z]+\.?\s?){1,3}\))?(?:\s?[A-Z]+\.?)?)\s*(?:No\.?\s*)?(\d{1,6})\s*/\s*((?:19|20)\d{2})\b")
AGGREGATE = re.compile(
    r"\b(how many|number of|what share|what percentage|what proportion|percentage of|share of|"
    r"count of|how often|appeared most|appear most|most often|most frequently|success rate)\b", re.I)
COMPLEX = re.compile(
    r"\b(compare|comparison|compared|before and after|both\b.+\band\b|later (?:considered|reversed|appealed|set aside)|"
    r"on appeal|appeal chain|overturned|reversed|over the years|trend|in each of|differ(?:ence|ently)?|later|"
    r"high court and (?:the )?supreme court|supreme court and (?:the )?high court|and (?:was )?also)\b", re.I)
PARTY = re.compile(r"^(?:.*?\b(?:judgment|judgement|case|order|decision|matter)s?\s+(?:in|of|titled)\s+)?"
                   r"(?P<a>[^?]+?)\s+(?:v\.?|vs\.?|versus)\s+(?P<b>[^?.]+)", re.I)
ONE_PARTY = re.compile(r"\b(?:in which|where)\s+(?P<a>(?:[A-Z][\w&.]*\s?){1,5})\s+(?:was|is|were)\s+(?:a\s+)?(?:party|petitioner|respondent|appellant)", re.I)
# Parties in thousands of matters: naming one does not pick out a case.
GENERIC_PARTY = re.compile(r"\b(union of india|state|government|govt|nct of delhi|commissioner|department|"
                           r"municipal corporation|delhi development authority|dda)\b", re.I)
LOOKUP_WORDS = re.compile(r"^\s*(show|find|open|get|pull up|fetch|give)\b|\b(judgment|judgement|order) (in|of)\b", re.I)


def route(question: str) -> dict:
    q = " ".join(question.split())
    m = CASE_NO.search(q)
    if m and not AGGREGATE.search(q):
        return {"route": "lookup", "reason": "case number", "case_number": (m.group(1).strip(), m.group(2), m.group(3))}
    if AGGREGATE.search(q):
        return {"route": "aggregate", "reason": f"counting words: {AGGREGATE.search(q).group(0)!r}"}
    if COMPLEX.search(q):
        return {"route": "complex", "reason": f"comparison or multi-stage words: {COMPLEX.search(q).group(0)!r}"}
    p = PARTY.search(q)
    if p and len(q.split()) <= 16:
        a, b = _clean_party(p.group("a")), _clean_party(p.group("b"))
        if a and b:
            return {"route": "lookup", "reason": "party names", "parties": (a, b)}
    o = ONE_PARTY.search(q)
    if o and _names(o.group("a")) and not GENERIC_PARTY.search(o.group("a")):
        return {"route": "lookup", "reason": "named party", "parties": (" ".join(_names(o.group("a"))), "")}
    if LOOKUP_WORDS.search(q) and len(q.split()) <= 14 and _proper_nouns(q) >= 2 and not GENERIC_PARTY.search(q):
        return {"route": "lookup", "reason": "named party", "parties": (" ".join(_names(q)), "")}
    return {"route": "simple", "reason": "one matter"}


_LEAD = re.compile(r"^(?:show|find|open|get|pull up|fetch|give)(?: me)?(?: the)?\s+", re.I)


def _clean_party(s: str) -> str:
    s = _LEAD.sub("", s.strip(" .,'\""))
    return " ".join(s.split()[-6:])


_NOT_NAMES = {"show", "find", "open", "get", "give", "fetch", "the", "judgment", "judgement", "cases", "case", "in",
              "which", "where", "was", "a", "party", "disputes", "decisions", "judgments", "of", "on", "for", "me"}


def _names(q: str) -> list[str]:
    return [w.strip(".,?") for w in q.split() if w[:1].isupper() and w.lower().strip(".,?") not in _NOT_NAMES]


def _proper_nouns(q: str) -> int:
    return len(_names(q))
