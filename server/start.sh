#!/bin/sh
# Starts the Brieflee knowledge service. knowledge.db comes from, in order:
# an existing file at $KNOWLEDGE_DB, the split copy in knowledge/, or KNOWLEDGE_DB_URL.
set -e
mkdir -p "$(dirname "$KNOWLEDGE_DB")"
if [ ! -s "$KNOWLEDGE_DB" ]; then
  if ls knowledge/knowledge.db.gz.part-* >/dev/null 2>&1; then
    echo "Unpacking knowledge layer from knowledge/…"
    cat knowledge/knowledge.db.gz.part-* | gunzip > "$KNOWLEDGE_DB"
  elif [ -n "$KNOWLEDGE_DB_URL" ]; then
    echo "Downloading knowledge layer…"
    python -c "import os,urllib.request; urllib.request.urlretrieve(os.environ['KNOWLEDGE_DB_URL'], os.environ['KNOWLEDGE_DB'] + '.gz')"
    gunzip -f "$KNOWLEDGE_DB.gz"
  else
    echo "No knowledge.db: add knowledge/ parts or set KNOWLEDGE_DB_URL" >&2
    exit 1
  fi
fi
exec uvicorn app:app --app-dir server --host 0.0.0.0 --port "${PORT:-8000}"
