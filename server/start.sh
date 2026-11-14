#!/bin/sh
# Starts the Brieflee knowledge service. knowledge.db comes from, in order:
# an existing file at $KNOWLEDGE_DB, KNOWLEDGE_DB_PARTS (space-separated URLs of
# the gzipped database split into parts, joined in order), the split copy in
# knowledge/, or KNOWLEDGE_DB_URL (one gzipped file).
set -e
mkdir -p "$(dirname "$KNOWLEDGE_DB")"
if [ ! -s "$KNOWLEDGE_DB" ]; then
  if [ -n "$KNOWLEDGE_DB_PARTS" ]; then
    echo "Downloading knowledge layer ($(echo $KNOWLEDGE_DB_PARTS | wc -w) parts)…"
    python - <<'PY'
import gzip, os, shutil, urllib.request

class Joined:
    """Reads the parts one after another as a single stream."""
    def __init__(self, urls):
        self.urls, self.cur = list(urls), None
    def read(self, n=-1):
        while True:
            if self.cur is None:
                if not self.urls:
                    return b""
                self.cur = urllib.request.urlopen(self.urls.pop(0), timeout=600)
            data = self.cur.read(n)
            if data:
                return data
            self.cur.close()
            self.cur = None

out = os.environ["KNOWLEDGE_DB"]
with gzip.GzipFile(fileobj=Joined(os.environ["KNOWLEDGE_DB_PARTS"].split())) as src, open(out + ".tmp", "wb") as dst:
    shutil.copyfileobj(src, dst, 16 << 20)
os.replace(out + ".tmp", out)
print("knowledge layer ready:", os.path.getsize(out) // (1 << 20), "MB")
PY
  elif ls knowledge/knowledge.db.gz.part-* >/dev/null 2>&1; then
    echo "Unpacking knowledge layer from knowledge/…"
    cat knowledge/knowledge.db.gz.part-* | gunzip > "$KNOWLEDGE_DB"
  elif [ -n "$KNOWLEDGE_DB_URL" ]; then
    echo "Downloading knowledge layer…"
    python -c "import os,urllib.request; urllib.request.urlretrieve(os.environ['KNOWLEDGE_DB_URL'], os.environ['KNOWLEDGE_DB'] + '.gz')"
    gunzip -f "$KNOWLEDGE_DB.gz"
  else
    echo "No knowledge.db: set KNOWLEDGE_DB_PARTS, add knowledge/ parts or set KNOWLEDGE_DB_URL" >&2
    exit 1
  fi
fi
exec uvicorn app:app --app-dir server --host 0.0.0.0 --port "${PORT:-8000}"
