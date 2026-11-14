import json
import sys

j = json.load(open(sys.argv[1]))
i = j.get("interpretation", {})
print("reading:", i.get("reading"))
print("queries:", i.get("queries"))
print("method:", {k: j.get("method", {}).get(k) for k in ("understanding", "retrieval", "reranking")})
print("similar decisions:", j.get("similar_decisions"))
for c in j.get("cases", [])[:8]:
    print(f"  [{c.get('relevance')}] {c['title'][:70]} | {c.get('relevance_note')}")
print("counsel:", [c["name"] for c in j.get("counsel", [])[:5]])
