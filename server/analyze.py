"""Document analysis: chunk an uploaded judgment or pleading, find its issues,
and link each issue to similar decisions in the knowledge layer.

1. Chunk the text into overlapping passages (by paragraph).
2. With an LLM configured (Gemini or Claude): read the whole document once and return, as
   structured JSON, a short summary, the client's likely side, and the legal
   issues, each with a search query, the statutes it turns on and the chunks
   it comes from. Without one: each chunk becomes an "issue" whose query
   is its most distinctive words.
3. For every issue, retrieve similar decisions (BM25 over judgment text).
   Results are fused across issues with reciprocal-rank fusion, so a
   decision relevant to several issues rises.
4. Credit counsel on the winning side of outcome-eligible decisions, with the
   same smoothing and evidence threshold as /v1/ask.

The document is processed in memory and never stored.
"""
import json
import math
import re
from collections import Counter

import generate
import llm
from rag import STOP, KnowledgeLayer, Retrieved

MAX_CHARS = 600_000  # about 150k tokens; larger documents are refused, not cut
CHUNK_CHARS = 2400
OVERLAP_CHARS = 300

ISSUES_SCHEMA = {
    "type": "object",
    "properties": {
        "summary": {"type": "string"},
        "document_type": {"type": "string"},
        "client_side": {"type": "string", "enum": ["petitioner", "respondent", "unclear"]},
        "subject": {"type": "string"},
        "issues": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "title": {"type": "string"},
                    "search_query": {"type": "string"},
                    "statutes": {"type": "array", "items": {"type": "string"}},
                    "chunks": {"type": "array", "items": {"type": "integer"}},
                },
                "required": ["title", "search_query", "statutes", "chunks"],
                "additionalProperties": False,
            },
        },
    },
    "required": ["summary", "document_type", "client_side", "subject", "issues"],
    "additionalProperties": False,
}

SYSTEM = (
    "You read Indian court documents (judgments, petitions, plaints, written statements, arbitration "
    "pleadings) for a counsel-discovery product. Identify the distinct legal issues the matter turns on, "
    "so that each can be searched against a database of Delhi High Court judgments. For each issue give a "
    "short title, a search query of 6 to 15 plain words a judgment on the same point would contain "
    "(include section numbers and Act names, e.g. 'section 34 Arbitration and Conciliation Act patent "
    "illegality'), the statutes it turns on, and the numbers of the chunks it comes from. Give 2 to 6 issues, "
    "most important first. client_side is the side the person uploading most likely acts for: the party "
    "that filed or is challenging is 'petitioner'; say 'unclear' if the document does not show it. Use only "
    "what the document says; do not add facts. Write the summary in two or three plain sentences."
)


FACTS_SCHEMA = {
    "type": "object",
    "properties": {
        "court": {"type": "string"},
        "case_number": {"type": "string"},
        "petitioners": {"type": "array", "items": {"type": "string"}},
        "respondents": {"type": "array", "items": {"type": "string"}},
        "deciding_judges": {"type": "array", "items": {"type": "string"}},
        "document_type": {"type": "string", "enum": ["judgment", "order", "petition", "plaint", "written_statement", "appeal", "application", "other"]},
        "case_category": {"type": "string"},
        "procedural_stage": {"type": "string", "enum": ["about_to_file", "pending_interim", "pending_final_hearing", "decided_appeal_possible", "execution", "unclear"]},
        "client_side": {"type": "string", "enum": ["petitioner", "respondent", "unclear"]},
        "relief_sought": {"type": "string"},
        "statutes": {"type": "array", "items": {"type": "string"}},
        "counsel": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "name": {"type": "string"},
                    "side": {"type": "string", "enum": ["petitioner", "respondent"]},
                    "role": {"type": "string", "enum": ["senior_advocate", "advocate", "government_counsel"]},
                },
                "required": ["name", "side", "role"],
                "additionalProperties": False,
            },
        },
        "issues": {"type": "array", "items": {"type": "string"}},
        "summary": {"type": "string"},
    },
    "required": ["court", "case_number", "petitioners", "respondents", "deciding_judges", "document_type",
                 "case_category", "procedural_stage", "client_side", "relief_sought", "statutes", "counsel",
                 "issues", "summary"],
    "additionalProperties": False,
}

FACTS_SYSTEM = (
    "You extract case facts from Indian court documents for a counsel-discovery product. Use only what the document "
    "states; use an empty string or empty list when something is not stated, never a guess. "
    "deciding_judges are the judges who decided THIS document (the CORAM or signature), not the judge the matter may be "
    "listed before next. Write statutes as 's.<number> <Act name, year>' for sections (e.g. 's.34 Arbitration and "
    "Conciliation Act, 1996') or the Act name alone. counsel are the advocates named for each side, without honorifics. "
    "issues are 2 to 6 legal questions the matter turns on, each a short plain-language phrase with the key terms a "
    "similar judgment would contain. case_category is a short label such as 'Arbitration: setting aside an award'. "
    "procedural_stage describes where the matter stands after this document: a final judgment or order means "
    "'decided_appeal_possible'. client_side is the side the uploader most likely acts for; 'unclear' if not evident. "
    "summary is two or three plain sentences."
)


def extract_facts(text: str) -> dict | None:
    """Structured case facts from the whole document (LLM), or None."""
    text = text.strip()
    if len(text) > MAX_CHARS:
        raise ValueError(f"Document is {len(text):,} characters; the limit is {MAX_CHARS:,}.")
    if not llm.available():
        return None
    facts = llm.complete_json(FACTS_SYSTEM, f"<document>\n{text}\n</document>\n\nExtract the case facts as JSON.", FACTS_SCHEMA)
    if facts is not None:
        facts["provider"] = llm.used_label()
    return facts


def chunk_document(text: str) -> list[str]:
    """Overlapping passages of about CHUNK_CHARS, split on paragraph breaks."""
    paras = [p.strip() for p in re.split(r"\n\s*\n|\n(?=\s*\d+\.\s)", text) if p.strip()]
    chunks, cur = [], ""
    for p in paras:
        while len(p) > CHUNK_CHARS:  # one very long paragraph
            head, p = p[:CHUNK_CHARS], p[CHUNK_CHARS - OVERLAP_CHARS:]
            if cur:
                chunks.append(cur)
                cur = ""
            chunks.append(head)
        if len(cur) + len(p) + 2 > CHUNK_CHARS and cur:
            chunks.append(cur)
            cur = cur[-OVERLAP_CHARS:] + "\n\n" + p
        else:
            cur = f"{cur}\n\n{p}" if cur else p
    if cur:
        chunks.append(cur)
    return chunks


def _llm_issues(chunks: list[str]) -> dict | None:
    if not llm.available():
        return None
    doc = "\n\n".join(f"[CHUNK {i + 1}]\n{c}" for i, c in enumerate(chunks))
    try:
        plan = llm.complete_json(SYSTEM, f"<document>\n{doc}\n</document>\n\nList the issues as JSON.", ISSUES_SCHEMA)
    except Exception:
        return None
    if not plan or not plan.get("issues"):
        return None
    return plan


def _keyword_issues(chunks: list[str], limit: int = 8) -> dict:
    """Fallback without an LLM: the most distinctive words of each chunk."""
    docs = [Counter(w for w in re.findall(r"[a-z][a-z\-]{3,}", c.lower()) if w not in STOP) for c in chunks]
    df = Counter(w for d in docs for w in d)
    n = len(docs)
    issues = []
    for i, d in enumerate(docs):
        ranked = sorted(d, key=lambda w: d[w] * math.log(1 + n / df[w]), reverse=True)[:14]
        sections = sorted(set(re.findall(r"\bsection\s+(\d+[A-Z]?)\b", chunks[i], re.I)))[:3]
        if len(ranked) < 4:
            continue
        issues.append({"title": f"Passage {i + 1}", "search_query": " ".join(ranked + [f"section {s}" for s in sections]),
                       "statutes": [], "chunks": [i + 1]})
    # Keep the chunks with the most legal vocabulary, spread through the document.
    if len(issues) > limit:
        step = len(issues) / limit
        issues = [issues[int(k * step)] for k in range(limit)]
    return {"summary": None, "document_type": None, "client_side": "unclear", "subject": None, "issues": issues}


def analyze(kl: KnowledgeLayer, text: str, side: str | None = None, per_issue: int = 60,
            confirmed: dict | None = None) -> dict:
    """confirmed: facts the user checked ({"issues": [...], "statutes": [...],
    "summary": str}); when given, they drive the search instead of a new reading."""
    text = text.strip()
    if len(text) > MAX_CHARS:
        raise ValueError(f"Document is {len(text):,} characters; the limit is {MAX_CHARS:,}. Upload the main judgment or pleading only.")
    chunks = chunk_document(text) if text else []
    if confirmed and confirmed.get("issues"):
        statutes = confirmed.get("statutes") or []
        plan = {"summary": confirmed.get("summary"), "document_type": None, "client_side": "unclear",
                "subject": confirmed.get("subject"),
                "issues": [{"title": i, "search_query": i, "statutes": statutes, "chunks": []} for i in confirmed["issues"]]}
        method = "confirmed"
    else:
        plan = _llm_issues(chunks)
        method = (llm.last_used or llm.provider() or "keywords") if plan else "keywords"
        if plan is None:
            plan = _keyword_issues(chunks)
    if side is None and plan.get("client_side") in ("petitioner", "respondent"):
        side = plan["client_side"][0]

    fused: dict[str, Retrieved] = {}
    rrf: Counter = Counter()
    issues_out = []
    for issue in plan["issues"]:
        query = " ".join([issue["search_query"], *issue.get("statutes", [])])
        interp = kl.interpret(query, side)
        hits = kl.retrieve(interp, k=per_issue)
        for rank, h in enumerate(hits):
            rrf[h.record_id] += 1.0 / (60 + rank)
            fused.setdefault(h.record_id, h)
        issues_out.append({
            "title": issue["title"],
            "search_query": issue["search_query"],
            "statutes": issue.get("statutes", []),
            "chunks": issue.get("chunks", []),
            "subjects": [label for _, label in interp["subjects"]],
            "cases": [kl.record_card(h) for h in hits[:5]],
            "similar_decisions": len(hits),
        })

    merged = []
    for rid, s in rrf.most_common(150):
        h = fused[rid]
        merged.append(Retrieved(h.record_id, s * 1000, h.passage, h.meta))
    counsel = kl.counsel_evidence(merged, side)
    ranked = [c for c in counsel if c["sufficient_evidence"]][:10]
    cases = [kl.record_card(h) for h in merged[:20]]
    answer = None
    if merged and plan.get("summary"):
        answer = generate.grounded_answer(
            f"Which counsel won matters like this one? The matter: {plan['summary']}", cases, ranked)

    return {
        "method": method,
        "chunks": len(chunks),
        "summary": plan.get("summary"),
        "document_type": plan.get("document_type"),
        "client_side": side,
        "subject": plan.get("subject"),
        "issues": issues_out,
        "similar_decisions": len(merged),
        "cases": cases,
        "counsel": ranked,
        "counsel_insufficient": [c for c in counsel if not c["sufficient_evidence"]][:15],
        "answer": answer,
        "attribution": kl.source.get("attribution"),
    }
