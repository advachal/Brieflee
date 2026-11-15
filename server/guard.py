"""Protection and observability for the public endpoints.

Rate limits: /v1/ask, /v1/analyze and /v1/extract are open to anyone, and each
can spend the AI provider's free quota. Per client address, at most
RATE_PER_MINUTE requests a minute (default 10) are served; more get HTTP 429.
Across all clients, at most DAILY_AI_QUESTIONS questions a day (default 400)
use the AI steps; after that, questions are still answered with keyword search
and the template answer, and the response says so.

Trace: with TRACE_PATH set, one JSON line per question records the route, the
steps and their timings, the top decision ids, the gate result and the AI
provider. The question itself is stored only as a SHA-256 hash unless
TRACE_QUESTIONS=1, because questions can hold a client's facts.

Integrity: with KNOWLEDGE_DB_SHA256 set, the database file is hashed in the
background at start-up. On a mismatch the service refuses questions (HTTP 503)
instead of answering from a database that is not the published one.
"""
import hashlib
import json
import os
import threading
import time
from collections import defaultdict, deque

RATE_PER_MINUTE = int(os.environ.get("RATE_PER_MINUTE", "10"))
DAILY_AI_QUESTIONS = int(os.environ.get("DAILY_AI_QUESTIONS", "400"))
TRACE_PATH = os.environ.get("TRACE_PATH")
TRACE_QUESTIONS = os.environ.get("TRACE_QUESTIONS") == "1"

_lock = threading.Lock()
_hits: dict[str, deque] = defaultdict(deque)
_day = {"date": "", "ai": 0}


def client_address(headers, fallback: str | None) -> str:
    fwd = headers.get("x-forwarded-for")
    return fwd.split(",")[0].strip() if fwd else (fallback or "unknown")


def allow(addr: str, now: float | None = None) -> bool:
    now = now or time.time()
    with _lock:
        q = _hits[addr]
        while q and q[0] <= now - 60:
            q.popleft()
        if len(q) >= RATE_PER_MINUTE:
            return False
        q.append(now)
        if len(_hits) > 10000:  # forget idle clients
            for k in [k for k, v in _hits.items() if not v][:5000]:
                del _hits[k]
        return True


def take_ai_budget() -> bool:
    """True if this question may use the AI steps today (counts it)."""
    today = time.strftime("%Y-%m-%d", time.gmtime())
    with _lock:
        if _day["date"] != today:
            _day.update(date=today, ai=0)
        if _day["ai"] >= DAILY_AI_QUESTIONS:
            return False
        _day["ai"] += 1
        return True


def budget_info() -> dict:
    return {"date": _day["date"], "ai_questions_used": _day["ai"], "ai_questions_per_day": DAILY_AI_QUESTIONS,
            "requests_per_minute_per_client": RATE_PER_MINUTE}


class Trace:
    def __init__(self, question: str):
        self.t0 = time.time()
        self.last = self.t0
        self.row = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    "question_sha256": hashlib.sha256(question.encode()).hexdigest()[:16], "steps": []}
        if TRACE_QUESTIONS:
            self.row["question"] = question

    def step(self, name: str, **info):
        now = time.time()
        self.row["steps"].append({"step": name, "ms": round(1000 * (now - self.last)), **info})
        self.last = now

    def set(self, **info):
        self.row.update(info)

    def summary(self) -> dict:
        return {"total_ms": round(1000 * (time.time() - self.t0)), "steps": [{k: s[k] for k in ("step", "ms")} for s in self.row["steps"]]}

    def write(self):
        if not TRACE_PATH:
            return
        self.row["total_ms"] = round(1000 * (time.time() - self.t0))
        try:
            with _lock, open(TRACE_PATH, "a") as f:
                f.write(json.dumps(self.row, ensure_ascii=False) + "\n")
        except OSError:
            pass


class Integrity:
    def __init__(self, path: str):
        self.expected = (os.environ.get("KNOWLEDGE_DB_SHA256") or "").split()[0].lower() if os.environ.get("KNOWLEDGE_DB_SHA256") else ""
        self.state = "not checked (KNOWLEDGE_DB_SHA256 not set)" if not self.expected else "checking"
        if self.expected:
            threading.Thread(target=self._run, args=(path,), daemon=True).start()

    def _run(self, path: str):
        h = hashlib.sha256()
        try:
            with open(path, "rb") as f:
                for block in iter(lambda: f.read(1 << 22), b""):
                    h.update(block)
        except OSError as e:
            self.state = f"error: {e}"
            return
        self.state = "ok" if h.hexdigest() == self.expected else "mismatch"

    @property
    def refused(self) -> bool:
        return self.state == "mismatch"
