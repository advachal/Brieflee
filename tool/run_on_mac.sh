#!/bin/bash
# Runs Brieflee on this Mac with the full knowledge database (Delhi High Court
# and Supreme Court, 2015 to 2025). Free; only you can use it.
#
#   curl -fsSL https://raw.githubusercontent.com/advachal/Brieflee/main/tool/run_on_mac.sh | bash
#
# First run downloads about 1.7 GB and needs about 8 GB of free disk. Later
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
curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/main" | tar -xz --strip-components=1 "Brieflee-main/server"
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

# 4. Optional: your Gemini key for the AI reading of uploaded documents.
#    Kept only in this folder (gemini.key), never sent anywhere but Google.
if [ ! -f gemini.key ]; then
  echo
  echo "Optional: paste your Gemini API key for AI document reading, then press Return."
  echo "(Press Return alone to skip; you can add it later in $HOME_DIR/gemini.key)"
  read -r -s KEY < /dev/tty || KEY=""
  printf '%s' "$KEY" > gemini.key
  chmod 600 gemini.key
fi
GEMINI_API_KEY=$(cat gemini.key)
export GEMINI_API_KEY KNOWLEDGE_DB="$HOME_DIR/knowledge.db" WEB_DIR="$HOME_DIR/web"
[ -n "$GEMINI_API_KEY" ] || unset GEMINI_API_KEY

echo
echo "== Starting. Open http://localhost:8000/Brieflee/ in Chrome (Control-C to stop)."
(sleep 4 && open "http://localhost:8000/Brieflee/") >/dev/null 2>&1 &
exec "$UV" run --python 3.12 --with-requirements server/requirements.txt \
  uvicorn app:app --app-dir server --host 127.0.0.1 --port 8000
