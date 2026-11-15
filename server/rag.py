"""Retrieval and knowledge-layer reasoning for Brieflee "Ask".

Pipeline for one question (all real time, nothing precomputed per question):
  1. Interpret: subject areas, statute sections, bench and side hints.
  2. Retrieve: BM25 (SQLite FTS5) over judgment text chunks from official
     Delhi High Court PDFs; best chunk per decision; subject filter by the
     registry case type.
  3. Reason over the knowledge layer: for retrieved decisions with an
     outcome-eligible result (petitioner side won / respondent side won),
     credit counsel on the winning side. Rates are smoothed toward 50% so
     3/3 does not outrank 40/50, and counsel below the evidence threshold
     are listed as "insufficient evidence", not ranked.
  4. Generate (optional): a short grounded answer from the retrieved
     passages, citing record ids. Without an API key the answer is a
     deterministic template over the same facts.
"""
import json
import re
import sqlite3
import threading
from dataclasses import dataclass, field

from subjects import detect
from vectors import VectorIndex

STOP = set("""a an and are as at be by can for from has have how i in is it its me my of on or our that the their this to
was we were what when which who whom will with would should could you your best lawyer advocate advocates counsel
find suggest recommend need needs want wants help case cases matter similar like delhi high court won win wins winning
client clients under section sections who has have had any please give show list top good which""".split())
SECTION_RX = re.compile(r"\b(?:section|sec\.?|s\.)\s*(\d+[a-z]?)\b", re.I)
PRIOR_STRENGTH = 10.0
MIN_ELIGIBLE = 3


@dataclass
class Retrieved:
    record_id: str
    score: float
    passage: str
    meta: dict = field(default_factory=dict)


class KnowledgeLayer:
    def __init__(self, db_path: str):
        self._path = db_path
        self._local = threading.local()
        self.counsel = {r["id"]: r["name"] for r in self.db.execute("SELECT id, name FROM counsel")}
        self.source = {r["key"]: json.loads(r["value"]) for r in self.db.execute("SELECT key, value FROM source")}
        self.vectors = VectorIndex(db_path)
        self.has_edges = bool(self.db.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'edges'").fetchone())

    @property
    def db(self) -> sqlite3.Connection:
        """One read-only connection per thread: the web server answers requests
        (and health checks) on several threads, and a SQLite connection must
        not be shared between them."""
        conn = getattr(self._local, "conn", None)
        if conn is None:
            conn = sqlite3.connect(f"file:{self._path}?mode=ro", uri=True, check_same_thread=False)
            conn.row_factory = sqlite3.Row
            self._local.conn = conn
        return conn

    # 1. Interpret --------------------------------------------------------
    def interpret(self, question: str, side: str | None = None) -> dict:
        subjects = detect(question)
        sections = sorted({m.group(1).upper() for m in SECTION_RX.finditer(question)})
        words = [w for w in re.findall(r"[a-z][a-z\-]{2,}", question.lower()) if w not in STOP]
        if side is None:
            q = question.lower()
            if re.search(r"\b(respondent|defend|defending|opposing|against me|i was sued)\b", q):
                side = "r"
            elif re.search(r"\b(petitioner|plaintiff|appellant|i want to (?:file|challenge|sue)|filing|wants? to (?:file|challenge|sue|set aside)|challeng\w*)\b", q):
                side = "p"
        return {"text": question, "subjects": [(s, l) for s, l, _ in subjects], "subject_matchers": [m for _, _, m in subjects],
                "sections": sections, "terms": words, "side": side}

    # 2. Retrieve -----------------------------------------------------------
    def retrieve(self, interp: dict, k: int = 120) -> list[Retrieved]:
        best = self._keyword_hits(interp)
        meaning = self._meaning_hits(interp.get("text", ""))
        if meaning:
            # Reciprocal rank fusion: a decision near the top of either list
            # (same words, or same meaning in other words) rises.
            kw = sorted(best.values(), key=lambda r: r.score, reverse=True)
            fused: dict[str, Retrieved] = {}
            for rank, r in enumerate(kw):
                fused[r.record_id] = Retrieved(r.record_id, 1.0 / (60 + rank), r.passage)
            for rank, r in enumerate(meaning):
                cur = fused.get(r.record_id)
                if cur is None:
                    fused[r.record_id] = Retrieved(r.record_id, 1.0 / (60 + rank), r.passage)
                else:
                    cur.score += 1.0 / (60 + rank)
            best = fused
        ids = list(best)
        metas = {}
        for i in range(0, len(ids), 500):
            batch = ids[i:i + 500]
            for m in self.db.execute(f"SELECT * FROM records WHERE id IN ({','.join('?' * len(batch))})", batch):
                metas[m["id"]] = dict(m)
        out = []
        for rid, r in best.items():
            m = metas.get(rid)
            if not m:
                continue
            # A matching case type lifts a decision; it no longer excludes others,
            # because the archive holds many courts and case types and a question
            # can name several subjects ("section 37" is arbitration and NDPS).
            if interp["subject_matchers"] and any(f(m["case_type"] or "") for f in interp["subject_matchers"]):
                r.score *= 1.6
            if interp["sections"]:
                acts = json.loads(m["acts"] or "[]")
                if any(any(a.startswith(f"s.{s} ") for a in acts) for s in interp["sections"]):
                    r.score *= 1.5
            r.meta = m
            out.append(r)
        out.sort(key=lambda x: x.score, reverse=True)
        return out[:k]

    def _keyword_hits(self, interp: dict) -> dict[str, Retrieved]:
        terms = list(dict.fromkeys(interp["terms"] + [f"section {s}" for s in interp["sections"]]))
        if not terms:
            return {}
        fts = " OR ".join('"' + t.replace('"', "") + '"' for t in terms[:24])
        rows = self.db.execute(
            """SELECT c.record_id, bm25(chunks_fts) AS s, snippet(chunks_fts, 0, '[', ']', ' … ', 40) AS snip
               FROM chunks_fts JOIN chunks c ON c.rowid = chunks_fts.rowid
               WHERE chunks_fts MATCH ? ORDER BY s LIMIT 4000""", (fts,)).fetchall()
        best: dict[str, Retrieved] = {}
        for r in rows:
            score = -r["s"]  # bm25() is lower-is-better
            cur = best.get(r["record_id"])
            if cur is None:
                best[r["record_id"]] = Retrieved(r["record_id"], score, r["snip"])
            else:
                cur.score += 0.15 * score  # several matching passages: a little extra weight
        return best

    def _meaning_hits(self, text: str) -> list[Retrieved]:
        """Decisions whose passages are closest in meaning, best first."""
        if not self.vectors.ready:
            return []
        chunks = self.vectors.search(text)
        if not chunks:
            return []
        rows = {}
        ids = [c for c, _ in chunks]
        for i in range(0, len(ids), 500):
            batch = ids[i:i + 500]
            for r in self.db.execute(f"SELECT rowid, record_id, text FROM chunks WHERE rowid IN ({','.join('?' * len(batch))})", batch):
                rows[r["rowid"]] = r
        out: dict[str, Retrieved] = {}
        for cid, sim in chunks:
            r = rows.get(cid)
            if r is None or r["record_id"] in out:
                continue
            t = " ".join(r["text"].split())
            out[r["record_id"]] = Retrieved(r["record_id"], sim, t[:320] + (" …" if len(t) > 320 else ""))
        return list(out.values())

    # Citation and appeal graph (edges table; see tool/knowledge/build_edges.py)
    def appeals_against(self, record_ids: list[str]) -> dict[str, dict]:
        """{lower record id: the appeal decided against it}, from appeal_of edges."""
        if not self.has_edges or not record_ids:
            return {}
        out = {}
        for i in range(0, len(record_ids), 500):
            b = record_ids[i:i + 500]
            q = (f"SELECT e.dst, r.id, r.case_number, r.decision_date, r.outcome FROM edges e JOIN records r ON r.id = e.src "
                 f"WHERE e.kind = 'appeal_of' AND e.dst IN ({','.join('?' * len(b))}) ORDER BY r.decision_date")
            for row in self.db.execute(q, b):
                out[row[0]] = {"id": row[1], "case_number": row[2], "decision_date": row[3], "outcome": row[4]}
        return out

    def graph(self, record_id: str, limit: int = 50) -> dict:
        """What a decision cites, what cites it, and its appeals both ways."""
        if not self.has_edges:
            return {"available": False}

        def side(sql):
            return [{"id": r[0], "case_number": r[1], "title": f"{r[2]} v. {r[3]}", "decision_date": r[4], "outcome": r[5],
                     "evidence": r[6]} for r in self.db.execute(sql, (record_id, limit))]
        cols = "r.id, r.case_number, r.petitioner, r.respondent, r.decision_date, r.outcome, e.evidence"
        return {"available": True,
                "cites": side(f"SELECT {cols} FROM edges e JOIN records r ON r.id = e.dst WHERE e.src = ? AND e.kind = 'cites' LIMIT ?"),
                "cited_by": side(f"SELECT {cols} FROM edges e JOIN records r ON r.id = e.src WHERE e.dst = ? AND e.kind = 'cites' ORDER BY r.decision_date DESC LIMIT ?"),
                "appeal_from": side(f"SELECT {cols} FROM edges e JOIN records r ON r.id = e.dst WHERE e.src = ? AND e.kind = 'appeal_of' LIMIT ?"),
                "appealed_in": side(f"SELECT {cols} FROM edges e JOIN records r ON r.id = e.src WHERE e.dst = ? AND e.kind = 'appeal_of' LIMIT ?")}

    # 3. Reason over the knowledge layer ------------------------------------
    def counsel_evidence(self, hits: list[Retrieved], side: str | None) -> list[dict]:
        if not hits:
            return []
        # A result later reversed on appeal is not a win (or loss) for anyone:
        # it is set aside and not counted.
        appeals = self.appeals_against([h.record_id for h in hits if h.meta.get("outcome") in ("petitioner", "respondent")])
        reversed_ids = {rid for rid, a in appeals.items() if a["outcome"] in ("petitioner", "partly")}
        top = hits[0].score or 1.0
        stats: dict[int, dict] = {}
        for h in hits:
            outcome = h.meta["outcome"]
            sim = max(h.score / top, 0.05)
            apps = self.db.execute("SELECT counsel_id, side, role FROM appearances WHERE record_id = ?", (h.record_id,)).fetchall()
            for a in apps:
                if a["role"] == "gov":
                    continue  # government panels are assigned, not chosen
                s = stats.setdefault(a["counsel_id"], {"similar": [], "wins": [], "losses": [], "other": [], "sides": {"p": 0, "r": 0}, "w": 0.0, "wl": 0.0})
                s["similar"].append(h.record_id)
                s["sides"][a["side"]] += 1
                if outcome in ("petitioner", "respondent") and h.record_id not in reversed_ids:
                    won = (outcome == "petitioner") == (a["side"] == "p")
                    (s["wins"] if won else s["losses"]).append(h.record_id)
                    s["w"] += sim * (1 if won else 0)
                    s["wl"] += sim
                else:
                    s["other"].append(h.record_id)
        rows = []
        for cid, s in stats.items():
            eligible = len(s["wins"]) + len(s["losses"])
            smoothed = (s["w"] + 0.5 * PRIOR_STRENGTH) / (s["wl"] + PRIOR_STRENGTH)
            side_fit = 1.0 if side is None else (s["sides"].get(side, 0) / max(1, sum(s["sides"].values())))
            relevance = min(len(s["similar"]) / 10.0, 1.0)
            score = 0.60 * smoothed + 0.25 * relevance + 0.15 * side_fit
            rows.append({
                "counsel_id": cid, "name": self.counsel.get(cid, "?"),
                "similar_matters": len(s["similar"]), "eligible_outcomes": eligible,
                "favourable": len(s["wins"]), "unfavourable": len(s["losses"]),
                "smoothed_favourable_rate": round(smoothed, 3), "score": round(score * 100, 1),
                "sufficient_evidence": eligible >= MIN_ELIGIBLE and len(s["wins"]) > 0 and smoothed >= 0.5,
                "evidence": {"similar": s["similar"], "favourable": s["wins"], "unfavourable": s["losses"], "not_eligible": s["other"],
                             "reversed_on_appeal": [r for r in s["other"] if r in reversed_ids]},
                "sides": s["sides"],
            })
        rows.sort(key=lambda r: (r["sufficient_evidence"], r["score"], r["similar_matters"]), reverse=True)
        return rows

    def texts(self, record_ids: list[str], max_chars: int = 400_000) -> dict[str, str]:
        """Full text of each decision (its chunks joined), for checking quotations."""
        out = {}
        for rid in record_ids:
            rows = self.db.execute("SELECT text FROM chunks WHERE record_id = ? ORDER BY chunk_index", (rid,)).fetchall()
            out[rid] = " ".join(r["text"] for r in rows)[:max_chars]
        return out

    def record_card(self, h: Retrieved, rating: dict | None = None, appeal: dict | None = None) -> dict:
        m = h.meta
        return {"appeal": appeal, "relevance": rating.get("relevance") if rating else None, "relevance_note": rating.get("why") if rating else None,
                "id": m["id"], "case_number": m["case_number"], "title": f"{m['petitioner']} v. {m['respondent']}",
                "decision_date": m["decision_date"], "judges": json.loads(m["judges"]), "outcome": m["outcome"],
                "outcome_evidence": m["outcome_evidence"], "passage": h.passage, "pdf_url": m["pdf_url"],
                "statutes": json.loads(m["acts"] or "[]"), "score": round(h.score, 2)}
