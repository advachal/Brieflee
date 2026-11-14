"""Brieflee knowledge service (RAG over official Delhi High Court judgments).

    pip install -r server/requirements.txt
    python tool/knowledge/build_knowledge.py          # builds build/knowledge/knowledge.db
    KNOWLEDGE_DB=build/knowledge/knowledge.db uvicorn app:app --app-dir server --port 8080

Optional: set ANTHROPIC_API_KEY to add a grounded, cited narrative answer.
Point the Flutter app at it with --dart-define=BRIEFLEE_API_BASE_URL=http://localhost:8080
"""
import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

import generate
from rag import KnowledgeLayer

DB = os.environ.get("KNOWLEDGE_DB", os.path.join(os.path.dirname(__file__), "..", "build", "knowledge", "knowledge.db"))
kl = KnowledgeLayer(DB)
app = FastAPI(title="Brieflee knowledge service", version="0.1")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["GET", "POST"], allow_headers=["*"])


class AskRequest(BaseModel):
    question: str
    side: str | None = None  # "p" petitioner/appellant, "r" respondent
    limit: int = 20


@app.get("/v1/health")
def health():
    n = kl.db.execute("SELECT count(*) FROM records").fetchone()[0]
    return {"ok": True, "records": n, "generation": generate.available(), "source": kl.source}


@app.post("/v1/ask")
def ask(req: AskRequest):
    interp = kl.interpret(req.question, req.side)
    hits = kl.retrieve(interp)
    counsel = kl.counsel_evidence(hits, interp["side"])
    cases = [kl.record_card(h) for h in hits[: req.limit]]
    ranked = [c for c in counsel if c["sufficient_evidence"]][:10]
    answer = generate.grounded_answer(req.question, cases, ranked) if hits else None
    return {
        "question": req.question,
        "interpretation": {"subjects": [l for _, l in interp["subjects"]], "sections": interp["sections"],
                           "terms": interp["terms"], "side": interp["side"]},
        "answer": answer,
        "answer_kind": "generated_grounded" if answer else "template",
        "similar_decisions": len(hits),
        "cases": cases,
        "counsel": ranked,
        "counsel_insufficient": [c for c in counsel if not c["sufficient_evidence"]][:15],
        "method": {
            "retrieval": "BM25 (SQLite FTS5) over text of official Delhi High Court judgments",
            "outcomes": "rule-based reading of the operative sentence; settled, withdrawn, interim and unclear orders excluded",
            "smoothing": f"favourable rate smoothed toward 50% with prior strength {10}",
            "evidence_threshold": "at least 3 outcome-eligible similar decisions",
        },
        "attribution": kl.source.get("attribution"),
    }
