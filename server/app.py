"""Brieflee knowledge service (RAG over official Delhi High Court judgments).

    pip install -r server/requirements.txt
    python tool/knowledge/build_knowledge.py          # builds build/knowledge/knowledge.db
    KNOWLEDGE_DB=build/knowledge/knowledge.db uvicorn app:app --app-dir server --port 8080

Optional: set GEMINI_API_KEY (or ANTHROPIC_API_KEY) for AI document analysis and a grounded, cited answer.
Point the Flutter app at it with --dart-define=BRIEFLEE_KNOWLEDGE_URL=http://localhost:8080

POST /v1/ask      a question in plain words. Routed first (router.py): a named case is looked up
                  directly, a count is answered from the database (direct.py), and a search
                  question runs understand → hybrid search → re-rank → answer → answer gate (gate.py).
                  Rate limits, the daily AI cap, the trace log and the database checksum: guard.py.
POST /v1/analyze  an uploaded document's text: chunked, issues found (Gemini or Claude), linked to similar decisions
"""
import os
import re

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

import analyze as analysis
import direct
import gate
import generate
import guard
import llm
import router
import understand as understanding
from rag import KnowledgeLayer

DB = os.environ.get("KNOWLEDGE_DB", os.path.join(os.path.dirname(__file__), "..", "build", "knowledge", "knowledge.db"))
kl = KnowledgeLayer(DB)
integrity = guard.Integrity(DB)
app = FastAPI(title="Brieflee knowledge service", version="0.2")


@app.middleware("http")
async def rate_limit(request: Request, call_next):
    if request.method == "POST" and request.url.path.startswith("/v1/"):
        addr = guard.client_address(request.headers, request.client.host if request.client else None)
        if not guard.allow(addr):
            return JSONResponse({"detail": "Too many requests: please wait a minute."}, status_code=429,
                                headers={"Retry-After": "60", "Access-Control-Allow-Origin": "*"})
    return await call_next(request)


app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["GET", "POST"], allow_headers=["*"])


class AnalyzeRequest(BaseModel):
    text: str = ""
    side: str | None = None  # "p" or "r"; inferred from the document when omitted
    facts: dict | None = None  # user-confirmed {"issues", "statutes", "summary", "subject"}


class ExtractRequest(BaseModel):
    text: str


class AskRequest(BaseModel):
    question: str
    side: str | None = None  # "p" petitioner/appellant, "r" respondent
    limit: int = 20


@app.get("/v1/health")
def health():
    n = kl.db.execute("SELECT count(*) FROM records").fetchone()[0]
    return {"ok": True, "records": n, "generation": generate.available(),
            "document_analysis": llm.label() or "keywords", "search_by_meaning": kl.vectors.info(), "recent_ai_errors": llm.recent_errors,
            "database_integrity": integrity.state, "limits": guard.budget_info(), "source": kl.source}


@app.post("/v1/extract")
def extract(req: ExtractRequest):
    """Case facts from an uploaded document, for the user to check before searching."""
    if len(req.text.strip()) < 200:
        raise HTTPException(422, "Not enough text in the document.")
    try:
        facts = analysis.extract_facts(req.text)
    except ValueError as e:
        raise HTTPException(413, str(e))
    except Exception as e:
        raise HTTPException(500, f"Extraction failed: {type(e).__name__}: {e}")
    if facts is None:
        raise HTTPException(503, "No AI provider is configured on the server.")
    return facts


@app.post("/v1/analyze")
def analyze(req: AnalyzeRequest):
    """Chunk an uploaded document, find its issues and link them to the knowledge layer."""
    if len(req.text.strip()) < 200 and not (req.facts and req.facts.get("issues")):
        raise HTTPException(422, "Not enough text in the document.")
    try:
        return analysis.analyze(kl, req.text, req.side, confirmed=req.facts)
    except ValueError as e:
        raise HTTPException(413, str(e))
    except Exception as e:  # report instead of dropping the connection
        raise HTTPException(500, f"Analysis failed: {type(e).__name__}: {e}")


@app.post("/v1/ask")
def ask(req: AskRequest, request: Request):
    if integrity.refused:
        raise HTTPException(503, "The knowledge database does not match its published checksum.")
    trace = guard.Trace(req.question)
    r = router.route(req.question)
    trace.step("route", route=r["route"], reason=r["reason"])
    try:
        out = None
        if r["route"] == "lookup":
            out = _lookup(req, r, trace)
        elif r["route"] == "aggregate":
            out = _aggregate(req, r, trace)
        if out is None:  # simple, complex, or a lookup/count that found nothing
            out = _search(req, r, trace)
        out["route"] = {"route": out.get("route_used", r["route"]), "reason": r["reason"]}
        out.pop("route_used", None)
        out["timing"] = trace.summary()
        return out
    finally:
        trace.write()


def _base(req: AskRequest, interp: dict, side, extra: dict | None = None) -> dict:
    return {"question": req.question,
            "interpretation": {"subjects": [l for _, l in interp["subjects"]], "sections": interp["sections"],
                               "terms": interp["terms"], "side": side, "reading": None, "statutes": [], "queries": []},
            "counsel": [], "counsel_insufficient": [], "attribution": kl.source.get("attribution"), **(extra or {})}


def _lookup(req: AskRequest, r: dict, trace) -> dict | None:
    if "case_number" in r:
        hits = direct.by_case_number(kl, *r["case_number"])
        what = " ".join(r["case_number"][:1]) + f" {r['case_number'][1]}/{r['case_number'][2]}"
    else:
        hits = direct.by_parties(kl, *r["parties"])
        what = " v. ".join(p for p in r["parties"] if p)
    trace.step("lookup", found=len(hits))
    trace.set(route="lookup", top_ids=[h.record_id for h in hits[:10]])
    if not hits:
        return None
    interp = kl.interpret(req.question, req.side)
    cases = [kl.record_card(h) for h in hits[: req.limit]]
    n = len(hits)
    answer = (f"Found {n} decision{'s' if n != 1 else ''} matching {what}" + (" (most recent first)." if n > 1 else ".")
              + " This is a direct lookup by " + ("case number." if "case_number" in r else "party names."))
    return _base(req, interp, interp["side"], {
        "answer": answer, "answer_kind": "lookup", "similar_decisions": n, "cases": cases,
        "gate": None, "method": {"retrieval": "direct lookup in the records table, no AI"}})


def _aggregate(req: AskRequest, r: dict, trace) -> dict | None:
    c = direct.count(kl, req.question)
    trace.step("count", ok=c.get("ok"), matched=c.get("matched"))
    trace.set(route="aggregate")
    if not c.get("ok"):
        return None
    interp = kl.interpret(req.question, req.side)
    side = interp["side"]
    ids = c.pop("_ids")
    counsel = []
    if re.search(r"appear(?:ed|s)? most|most often|most frequently", req.question, re.I):
        counsel = direct.top_counsel(kl, ids, side)
        trace.step("counsel_tally", advocates=len(counsel))
    answer = direct.count_answer(c)
    if counsel:
        answer += "\nMost frequent counsel" + (" for that side" if side else "") + ": " + \
                  "; ".join(f"{x['name']} ({x['appearances']})" for x in counsel[:8]) + "."
    sample = [kl.record_card(direct._hit(kl, m)) for m in
              kl.db.execute(f"SELECT * FROM records WHERE id IN ({','.join('?' * len(c['sample_ids']))})", c["sample_ids"])][: req.limit] if c["sample_ids"] else []
    return _base(req, interp, side, {
        "answer": answer, "answer_kind": "count", "similar_decisions": c["matched"], "cases": sample,
        "counts": c, "counsel_frequency": counsel, "gate": None,
        "method": {"retrieval": "database count over the records table, no AI", "rule": c["rule"]}})


def _search(req: AskRequest, r: dict, trace) -> dict:
    interp = kl.interpret(req.question, req.side)
    use_ai = llm.available() and guard.take_ai_budget()
    # 1. The model reads the question first (what is needed, which side, which
    #    statutes, how a matching judgment would put it).
    u = understanding.understand(req.question) if use_ai else None
    trace.step("understand", used=bool(u))
    side = interp["side"]
    if u:
        queries = [u["meaning_query"], *u.get("keyword_queries", [])[:3], req.question]
        if req.side is None and u.get("client_side") in ("petitioner", "respondent"):
            side = u["client_side"][0]
        statutes = u.get("statutes") or []
    else:
        queries, statutes = [req.question], []
    # 2. Hybrid search (keywords + meaning) for each reading, fused by rank.
    hits = understanding.search(kl, queries, side, statutes)
    trace.step("search", queries=len(queries), found=len(hits))
    # 3. The model checks the top decisions against the question and reorders them.
    context = req.question + (f"\n(Reading: {u['reading']})" if u and u.get("reading") else "")
    hits, ratings = understanding.rerank(context, hits) if use_ai else (hits, {})
    trace.step("rerank", rated=len(ratings))
    counsel = kl.counsel_evidence(hits, side)
    cases = [kl.record_card(h, ratings.get(h.record_id)) for h in hits[: req.limit]]
    ranked = [c for c in counsel if c["sufficient_evidence"]][:10]
    draft = generate.grounded_answer(req.question, cases, ranked) if (hits and use_ai) else None
    trace.step("answer", generated=bool(draft))
    # 4. The answer gate: citations and quotes must come from what was retrieved.
    given = [c["id"] for c in cases[:12]]
    verdict = gate.check(draft, given, kl.texts(given) if draft else {}, ratings, found=len(hits))
    answer, kind = gate.apply(draft, verdict)
    trace.step("gate", passed=verdict["passed"], problems=verdict["problems"], thin=verdict["thin_evidence"])
    trace.set(route=r["route"], provider=llm.used_label() if use_ai else None, top_ids=[h.record_id for h in hits[:10]],
              ratings={k: v.get("relevance") for k, v in list(ratings.items())[:30]})
    meaning = kl.vectors.ready
    return {
        "question": req.question,
        "interpretation": {"subjects": [l for _, l in interp["subjects"]], "sections": interp["sections"],
                           "terms": interp["terms"], "side": side,
                           "reading": u.get("reading") if u else None, "statutes": statutes,
                           "queries": queries if u else []},
        "answer": answer,
        "answer_kind": kind if answer or draft else "template",
        "gate": verdict,
        "similar_decisions": len(hits),
        "cases": cases,
        "counsel": ranked,
        "counsel_insufficient": [c for c in counsel if not c["sufficient_evidence"]][:15],
        "method": {
            "understanding": (llm.used_label() if u else None),
            "ai_budget": None if use_ai or not llm.available() else "daily AI limit reached: keyword search only",
            "retrieval": ("keywords (BM25) + meaning (bge-small embeddings), fused by rank" if meaning else "keywords (BM25)")
                         + f" over the text of {kl.source.get('name') or 'official Delhi High Court judgments'}",
            "reranking": (f"top {understanding.RERANK_TOP} checked by {llm.used_label()}" if ratings else None),
            "answer_check": "cited ids must be among the retrieved decisions and quotations must appear in them",
            "outcomes": "rule-based reading of the operative sentence; settled, withdrawn, interim and unclear orders excluded",
            "smoothing": f"favourable rate smoothed toward 50% with prior strength {10}",
            "evidence_threshold": "at least 3 outcome-eligible similar decisions",
        },
        "attribution": kl.source.get("attribution"),
    }


# Optional: serve the website from this service (the run-on-a-Mac script sets
# WEB_DIR to the built web app). The app is built for the path /Brieflee/.
WEB_DIR = os.environ.get("WEB_DIR")
if WEB_DIR and os.path.isdir(WEB_DIR):
    from fastapi.responses import FileResponse, RedirectResponse

    @app.get("/", include_in_schema=False)
    def web_root():
        return RedirectResponse("/Brieflee/")

    @app.get("/Brieflee/{path:path}", include_in_schema=False)
    def web(path: str = ""):
        root = os.path.realpath(WEB_DIR)
        f = os.path.realpath(os.path.join(root, path))
        if f.startswith(root + os.sep) and os.path.isfile(f):
            return FileResponse(f)
        return FileResponse(os.path.join(root, "index.html"))  # app routes

