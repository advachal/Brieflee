#!/bin/bash
# Runs Brieflee on this Mac with the full knowledge database (Delhi High Court
# and Supreme Court, 2015 to 2025). Free; only you can use it.
#
#   curl -fsSL https://raw.githubusercontent.com/advachal/Brieflee/main/tool/run_on_mac.sh | bash
#
# First run downloads about 2.7 GB and needs about 9 GB of free disk. Later
# runs start in seconds. Stop it with Control-C. Everything lives in
# ~/Brieflee-local; delete that folder to remove it.
set -euo pipefail
REPO=advachal/Brieflee
HOME_DIR="$HOME/Brieflee-local"
mkdir -p "$HOME_DIR"
cd "$HOME_DIR"

echo "== Brieflee on this Mac (folder: $HOME_DIR)"

# 1. A recent Python, via uv (installed into your home folder if missing).
if ! command -v uv >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/uv" ]; then
  echo "== Installing uv (Python manager)…"
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
UV=$(command -v uv || echo "$HOME/.local/bin/uv")

# 2. The server code and the website (latest from GitHub).
echo "== Fetching the server and website…"
# The server comes file by file from the latest commit (always current); the
# release zip is the fallback.
SHA=$(curl -fsSL -H "Accept: application/vnd.github.sha" "https://api.github.com/repos/$REPO/commits/main" 2>/dev/null || true)
FILES=""
[ -n "$SHA" ] && FILES=$(curl -fsSL "https://api.github.com/repos/$REPO/contents/server?ref=$SHA" 2>/dev/null \
  | grep '"type": "file"' -B20 | sed -n 's/.*"name": "\([^"]*\)".*/\1/p' || true)
if [ -n "$FILES" ]; then
  rm -rf server.new && mkdir server.new
  ok=1
  for f in $FILES; do curl -fsSL -o "server.new/$f" "https://raw.githubusercontent.com/$REPO/$SHA/server/$f" || ok=0; done
  if [ "$ok" = 1 ]; then rm -rf server && mv server.new server; else rm -rf server.new; FILES=""; fi
fi
if [ -z "$FILES" ]; then
  curl -fsSL -o server.zip "https://github.com/$REPO/releases/download/web-latest/brieflee-server.zip"
  rm -rf server && unzip -q -o server.zip && rm server.zip
fi
curl -fsSL -o web.zip "https://github.com/$REPO/releases/download/web-latest/brieflee-web.zip"
rm -rf web && unzip -q -o web.zip && rm web.zip

# 3. The knowledge database (only when it is missing or a newer one exists).
PARTS=$(curl -fsSL "https://github.com/$REPO/releases/download/knowledge-db/knowledge-db.parts")
WANT=$(curl -fsSL "https://github.com/$REPO/releases/download/knowledge-db/knowledge.db.sha256" | cut -d' ' -f1)
if [ ! -s knowledge.db ] || [ "$(cat knowledge.db.sha256 2>/dev/null)" != "$WANT" ]; then
  echo "== Downloading the knowledge database (about 1.7 GB, then unpacked to about 5 GB)…"
  rm -f knowledge.db
  for url in $PARTS; do curl -fL --retry 5 -C - -o "part.$(basename "$url")" "$url"; done
  cat part.* | gunzip > knowledge.db.tmp
  rm -f part.*
  mv knowledge.db.tmp knowledge.db
  echo "$WANT" > knowledge.db.sha256
fi

# 3b. Search by meaning: one vector per passage (about 1 GB), when published
#     for this database.
REL="https://github.com/$REPO/releases/download/knowledge-db"
EMB_FOR=$(curl -fsSL "$REL/knowledge.emb.sha256" 2>/dev/null | cut -d' ' -f1 || true)
if [ -n "$EMB_FOR" ] && [ "$EMB_FOR" = "$WANT" ] && [ "$(cat knowledge.emb.sha256 2>/dev/null)" != "$WANT" ]; then
  echo "== Downloading search by meaning (about 1 GB)…"
  curl -fL --retry 5 -o knowledge.emb.rowids "$REL/knowledge.emb.rowids"
  curl -fL --retry 5 -C - -o knowledge.emb.i8.part "$REL/knowledge.emb.i8"
  mv knowledge.emb.i8.part knowledge.emb.i8
  echo "$WANT" > knowledge.emb.sha256
elif [ -n "$EMB_FOR" ] && [ "$EMB_FOR" != "$WANT" ]; then
  rm -f knowledge.emb.i8 knowledge.emb.rowids knowledge.emb.sha256  # built for another database
fi

# 4. Optional AI keys for reading uploaded documents. Each is kept only in
#    this folder (groq.key, gemini.key) and sent only to that provider.
#    Groq is tried first; Gemini is used when Groq is unavailable.
ask_key() {  # file, prompt
  if [ ! -f "$1" ]; then
    echo
    echo "Optional: paste your $2 API key, then press Return."
    echo "(Press Return alone to skip; you can add it later in $HOME_DIR/$1)"
    read -r -s KEY < /dev/tty || KEY=""
    printf '%s' "$KEY" > "$1"
    chmod 600 "$1"
  fi
}
ask_key groq.key "Groq (free at console.groq.com)"
ask_key gemini.key "Gemini"
GROQ_API_KEY=$(cat groq.key); GEMINI_API_KEY=$(cat gemini.key)
export GROQ_API_KEY GEMINI_API_KEY KNOWLEDGE_DB="$HOME_DIR/knowledge.db" KNOWLEDGE_DB_SHA256="$WANT" TRACE_PATH="$HOME_DIR/trace.jsonl" WEB_DIR="$HOME_DIR/web"
[ -n "$GROQ_API_KEY" ] || unset GROQ_API_KEY
[ -n "$GEMINI_API_KEY" ] || unset GEMINI_API_KEY

echo
echo "== Starting. Open http://localhost:8000/Brieflee/ in Chrome (Control-C to stop)."
(sleep 4 && open "http://localhost:8000/Brieflee/") >/dev/null 2>&1 &
exec "$UV" run --no-project --isolated --python 3.12 --with-requirements server/requirements.txt \
  uvicorn app:app --app-dir server --host 127.0.0.1 --port 8000
