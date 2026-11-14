"""Embeds judgment chunks of the knowledge database for search by meaning.

  python build_embeddings.py knowledge.db OUT_DIR --shard 3 --shards 24
  python build_embeddings.py --merge OUT_DIR knowledge.emb.i8 knowledge.emb.rowids --shards 24

Each shard embeds a contiguous range of chunk rowids with BAAI/bge-small-en-v1.5
(fastembed, CPU) and writes shard-NN.i8 (int8, value x 127) and
shard-NN.rowids (int32). --merge joins the shards in order.
"""
import argparse
import os
import sqlite3
import sys
import time

import numpy as np

MODEL = "BAAI/bge-small-en-v1.5"
DIM = 384
MAX_CHARS = 1500


def embed_shard(db: str, out: str, shard: int, shards: int, batch: int) -> None:
    from fastembed import TextEmbedding
    conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    lo, hi = conn.execute("SELECT min(rowid), max(rowid) FROM chunks").fetchone()
    size = (hi - lo + 1 + shards - 1) // shards
    a, b = lo + shard * size, min(hi, lo + (shard + 1) * size - 1)
    rows = conn.execute("SELECT rowid, text FROM chunks WHERE rowid BETWEEN ? AND ? ORDER BY rowid", (a, b)).fetchall()
    print(f"shard {shard}/{shards}: rowids {a}..{b}, {len(rows)} chunks", flush=True)
    model = TextEmbedding(MODEL, threads=os.cpu_count())
    ids = np.array([r[0] for r in rows], dtype=np.int32)
    texts = (" ".join((r[1] or "").split())[:MAX_CHARS] for r in rows)
    vecs = np.empty((len(rows), DIM), dtype=np.int8)
    t0 = time.time()
    for n, v in enumerate(model.embed(texts, batch_size=batch)):
        v = np.asarray(v, dtype=np.float32)
        v /= np.linalg.norm(v) or 1.0
        vecs[n] = np.clip(np.round(v * 127), -127, 127).astype(np.int8)
        if n and n % 20000 == 0:
            print(f"  {n} chunks, {n / (time.time() - t0):.0f}/s", flush=True)
    os.makedirs(out, exist_ok=True)
    vecs.tofile(os.path.join(out, f"shard-{shard:02d}.i8"))
    ids.tofile(os.path.join(out, f"shard-{shard:02d}.rowids"))
    print(f"done in {time.time() - t0:.0f}s", flush=True)


def merge(src: str, emb: str, rowids: str, shards: int) -> None:
    n = 0
    with open(emb, "wb") as fe, open(rowids, "wb") as fi:
        for s in range(shards):
            for ext, f in (("i8", fe), ("rowids", fi)):
                with open(os.path.join(src, f"shard-{s:02d}.{ext}"), "rb") as g:
                    while chunk := g.read(1 << 24):
                        f.write(chunk)
            n += os.path.getsize(os.path.join(src, f"shard-{s:02d}.rowids")) // 4
    assert os.path.getsize(emb) == n * DIM, "vector and id counts differ"
    print(f"merged {n} vectors")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("args", nargs="+")
    p.add_argument("--shard", type=int, default=0)
    p.add_argument("--shards", type=int, default=1)
    p.add_argument("--batch", type=int, default=64)
    p.add_argument("--merge", action="store_true")
    a = p.parse_args()
    if a.merge:
        merge(*a.args, a.shards)
    else:
        embed_shard(*a.args, a.shard, a.shards, a.batch)
    sys.exit(0)
