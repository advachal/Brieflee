#!/bin/bash
# Sets up the Brieflee knowledge service with the FULL database on a Linux
# server (Ubuntu 22.04/24.04, e.g. an Oracle Cloud Always Free VM), served
# over HTTPS at https://<server-ip>.sslip.io (Caddy, automatic certificate).
#
#   curl -fsSL https://raw.githubusercontent.com/advachal/Brieflee/main/tool/setup_server.sh | sudo bash
#
# Asks once for the Groq key (and optionally Gemini), stored in
# /opt/brieflee/env (readable by root only). Re-run to update the code and the
# database. Needs ports 80 and 443 open to the internet.
set -euo pipefail
REPO=advachal/Brieflee
DIR=/opt/brieflee
mkdir -p "$DIR"
cd "$DIR"

echo "== Packages"
apt-get update -qq
apt-get install -y -qq curl unzip ca-certificates debian-keyring debian-archive-keyring apt-transport-https gnupg >/dev/null
if ! command -v caddy >/dev/null; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq && apt-get install -y -qq caddy >/dev/null
fi
if [ ! -x /usr/local/bin/uv ]; then
  curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
fi

echo "== Server code (latest)"
rm -rf code.tmp && mkdir code.tmp
curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/main" | tar -xz -C code.tmp --strip-components=1 "Brieflee-main/server"
rm -rf server && mv code.tmp/server server && rm -rf code.tmp

echo "== Knowledge database (only when missing or changed)"
REL="https://github.com/$REPO/releases/download/knowledge-db"
WANT=$(curl -fsSL "$REL/knowledge.db.sha256" | cut -d' ' -f1)
if [ ! -s knowledge.db ] || [ "$(cat knowledge.db.sha256 2>/dev/null)" != "$WANT" ]; then
  for u in $(curl -fsSL "$REL/knowledge-db.parts"); do curl -fsSL --retry 5 "$u"; done | gunzip > knowledge.db.tmp
  mv knowledge.db.tmp knowledge.db
  echo "$WANT" > knowledge.db.sha256
fi
EMB_FOR=$(curl -fsSL "$REL/knowledge.emb.sha256" 2>/dev/null | cut -d' ' -f1 || true)
if [ -n "$EMB_FOR" ] && [ "$EMB_FOR" = "$WANT" ] && [ "$(cat knowledge.emb.sha256 2>/dev/null)" != "$WANT" ]; then
  curl -fsSL --retry 5 -o knowledge.emb.rowids "$REL/knowledge.emb.rowids"
  curl -fsSL --retry 5 -o knowledge.emb.i8 "$REL/knowledge.emb.i8"
  echo "$WANT" > knowledge.emb.sha256
fi

echo "== Keys"
if [ ! -f env ]; then
  read -r -s -p "Groq API key (Return to skip): " GROQ < /dev/tty || GROQ=""; echo
  read -r -s -p "Gemini API key (Return to skip): " GEM < /dev/tty || GEM=""; echo
  umask 077
  { [ -n "$GROQ" ] && echo "GROQ_API_KEY=$GROQ"; [ -n "$GEM" ] && echo "GEMINI_API_KEY=$GEM"; true; } > env
fi
chmod 600 env

echo "== Service"
useradd -r -s /usr/sbin/nologin brieflee 2>/dev/null || true
chown -R brieflee "$DIR"; chown root env
mkdir -p /var/cache/brieflee-uv && chown brieflee /var/cache/brieflee-uv
cat > /etc/systemd/system/brieflee.service <<UNIT
[Unit]
Description=Brieflee knowledge service
After=network-online.target

[Service]
User=brieflee
WorkingDirectory=$DIR
EnvironmentFile=$DIR/env
Environment=KNOWLEDGE_DB=$DIR/knowledge.db UV_CACHE_DIR=/var/cache/brieflee-uv HOME=$DIR
ExecStart=/usr/local/bin/uv run --no-project --isolated --python 3.12 --with-requirements server/requirements.txt uvicorn app:app --app-dir server --host 127.0.0.1 --port 8000 --workers 2
Restart=always

[Install]
WantedBy=multi-user.target
UNIT
# The env file is root-only; systemd reads it before dropping to the brieflee user.
IP=$(curl -fsS https://api.ipify.org)
HOST="${IP//./-}.sslip.io"
cat > /etc/caddy/Caddyfile <<CADDY
$HOST {
  reverse_proxy 127.0.0.1:8000
}
CADDY
# Open the firewall inside the VM (Oracle images block 80/443 by default).
if command -v iptables >/dev/null; then
  for p in 80 443; do iptables -C INPUT -p tcp --dport $p -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport $p -j ACCEPT; done
  command -v netfilter-persistent >/dev/null && netfilter-persistent save >/dev/null 2>&1 || true
fi
systemctl daemon-reload
systemctl enable --now brieflee >/dev/null
systemctl restart brieflee caddy

echo
echo "== Done. The service is starting at https://$HOST (first start installs Python packages, about a minute)."
echo "   Check: curl https://$HOST/v1/health"
echo "   Tell Claude this address to point the website at it."
