"""Prints where known relevant decisions rank, keyword-only and with search
by meaning, for a few test questions. Run with KNOWLEDGE_DB set."""
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "server"))
from rag import KnowledgeLayer  # noqa: E402

CASES = [
    ("Registered design of an LED surface light; the defendant says the design was prior published, "
     "not new or original, and used as a trade mark, so the registration should be cancelled and no injunction granted",
     "DLHC010405542022_2022-11-16"),
    ("design infringement LED light prior publication novelty Designs Act section 22",
     "DLHC010405542022_2022-11-16"),
]

kl = KnowledgeLayer(os.environ["KNOWLEDGE_DB"])
print("search by meaning:", kl.vectors.info())
for q, want in CASES:
    for label, on in (("keywords only", False), ("keywords + meaning", True)):
        ready = kl.vectors.ready
        kl.vectors.ready = ready and on
        t = time.time()
        hits = kl.retrieve(kl.interpret(q), k=1000)
        kl.vectors.ready = ready
        ids = [h.record_id for h in hits]
        rank = ids.index(want) + 1 if want in ids else None
        print(f"[{label}] {time.time() - t:.1f}s rank of {want}: {rank}  | {q[:70]}")
        for h in hits[:5]:
            print("    ", h.record_id, (h.meta.get("petitioner") or "")[:40], "v", (h.meta.get("respondent") or "")[:40])
