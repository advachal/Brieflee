"""Prints a /v1/analyze response briefly (used by check-service.yml)."""
import json
import sys

raw = open(sys.argv[1]).read()
try:
    j = json.loads(raw)
except json.JSONDecodeError:
    print(raw[:2000])
    sys.exit(1)
if "issues" not in j:
    print(json.dumps(j)[:2000])
    sys.exit(1)
print("method:", j["method"], "| chunks:", j["chunks"], "| side:", j["client_side"])
print("summary:", j["summary"])
for i in j["issues"]:
    print(" -", i["title"], "|", i["similar_decisions"], "similar")
print("counsel:", [(c["name"], c["favourable"], c["unfavourable"]) for c in j["counsel"][:6]])
print("answer:", (j.get("answer") or "")[:400])
