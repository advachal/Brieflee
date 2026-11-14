#!/bin/sh
set -e
mkdir -p "$(dirname "$KNOWLEDGE_DB")"
if [ ! -s "$KNOWLEDGE_DB" ]; then
  if [ -z "$KNOWLEDGE_DB_URL" ]; then
    echo "Set KNOWLEDGE_DB_URL to the knowledge.db download URL" >&2
    exit 1
  fi
  echo "Downloading knowledge layer…"
  python -c "import os,urllib.request; urllib.request.urlretrieve(os.environ['KNOWLEDGE_DB_URL'], os.environ['KNOWLEDGE_DB'])"
  case "$KNOWLEDGE_DB_URL" in *.gz) mv "$KNOWLEDGE_DB" "$KNOWLEDGE_DB.gz" && gunzip "$KNOWLEDGE_DB.gz";; esac
fi
exec uvicorn app:app --app-dir server --host 0.0.0.0 --port "${PORT:-8000}"
