"""Search by meaning over the judgment chunks (optional).

Uses two files made by tool/archive/build_embeddings.py next to the knowledge
database (or at KNOWLEDGE_EMB / KNOWLEDGE_EMB_ROWIDS):
  knowledge.emb.i8      one 384-number vector per chunk, int8 (value x 127)
  knowledge.emb.rowids  the chunk rowid of each vector, int32
Vectors come from BAAI/bge-small-en-v1.5 (fastembed, runs on the CPU, no
API key). Without the files, or without fastembed installed, search by meaning
is off and retrieval is keyword (BM25) only.
"""
import os
import threading

MODEL = "BAAI/bge-small-en-v1.5"
DIM = 384
QUERY_PREFIX = "Represent this sentence for searching relevant passages: "
BLOCK = 131072


class VectorIndex:
    def __init__(self, db_path: str):
        base = os.path.splitext(db_path)[0]
        self.emb_path = os.environ.get("KNOWLEDGE_EMB", base + ".emb.i8")
        self.ids_path = os.environ.get("KNOWLEDGE_EMB_ROWIDS", base + ".emb.rowids")
        self._model = None
        self._lock = threading.Lock()
        self.ready = False
        self.error = None
        try:
            if not (os.path.exists(self.emb_path) and os.path.exists(self.ids_path)):
                self.error = "no embedding files"
                return
            import numpy as np
            self.np = np
            self.rowids = np.fromfile(self.ids_path, dtype=np.int32)
            self.emb = np.memmap(self.emb_path, dtype=np.int8, mode="r").reshape(-1, DIM)
            if len(self.emb) != len(self.rowids):
                self.error = f"{len(self.emb)} vectors but {len(self.rowids)} ids"
                return
            import fastembed  # noqa: F401  (checked now, loaded on first query)
            self.ready = True
        except Exception as e:  # missing numpy/fastembed, unreadable files
            self.error = f"{type(e).__name__}: {e}"

    def info(self) -> dict:
        return {"enabled": self.ready, "model": MODEL if self.ready else None,
                "chunks": int(len(self.rowids)) if self.ready else 0, "note": self.error}

    def _embed(self, text: str):
        with self._lock:
            if self._model is None:
                from fastembed import TextEmbedding
                self._model = TextEmbedding(MODEL)
        v = next(iter(self._model.embed([QUERY_PREFIX + text[:2000]])))
        v = self.np.asarray(v, dtype=self.np.float32)
        return v / (self.np.linalg.norm(v) or 1.0)

    def search(self, text: str, k: int = 600) -> list[tuple[int, float]]:
        """The k chunks closest in meaning: (chunk rowid, cosine similarity)."""
        if not self.ready or not text.strip():
            return []
        np = self.np
        q = self._embed(text)
        best_s, best_i = [], []
        for start in range(0, len(self.emb), BLOCK):
            block = np.asarray(self.emb[start:start + BLOCK], dtype=np.float32)
            s = block @ q
            kk = min(k, len(s))
            idx = np.argpartition(-s, kk - 1)[:kk]
            best_s.append(s[idx])
            best_i.append(idx + start)
        s = np.concatenate(best_s)
        i = np.concatenate(best_i)
        top = np.argsort(-s)[:k]
        return [(int(self.rowids[i[t]]), float(s[t]) / 127.0) for t in top]
