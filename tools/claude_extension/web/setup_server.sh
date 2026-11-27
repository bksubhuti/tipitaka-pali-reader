#!/bin/bash
# Sets up the TPR Research web server on a fresh Ubuntu 24.04 machine
# (a 1 GB DigitalOcean droplet is enough). Run as root:
#   DOMAIN=tpr.americanmonk.org bash setup_server.sh
# Safe to run again: it updates the server code and keeps the rest.
#
# Installs: a 1 GB swap file, firewall (SSH, HTTP, HTTPS), automatic
# security updates, Node 24, Google Chrome (headless, for paper PDFs) and
# Caddy (HTTPS with a Let's Encrypt certificate, renewed by itself).
# The server runs as the user `tpr` from /srv/tpr, as systemd service `tpr`.
set -euo pipefail
DOMAIN=${DOMAIN:?set DOMAIN, e.g. DOMAIN=tpr.americanmonk.org}
REPO=https://github.com/bksubhuti/tipitaka-pali-reader
DB_URL=https://github.com/bksubhuti/tpr_downloads/releases/download/server-db/tpr-server-db.tar.zst
export DEBIAN_FRONTEND=noninteractive

# ---- swap: Chrome needs a few hundred MB for a moment when printing a PDF
if ! swapon --show | grep -q /swapfile; then
  fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  grep -q /swapfile /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

apt-get update
apt-get install -y curl git zstd ufw unattended-upgrades debian-keyring debian-archive-keyring apt-transport-https gnupg

ufw allow OpenSSH && ufw allow 80/tcp && ufw allow 443/tcp && ufw --force enable

# ---- Node 24 (node:sqlite)
if ! node --version 2>/dev/null | grep -q '^v24'; then
  curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
  apt-get install -y nodejs
fi

# ---- Google Chrome (Ubuntu's chromium is a snap, awkward to run headless)
if ! command -v google-chrome >/dev/null; then
  curl -fsSL -o /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  apt-get install -y /tmp/chrome.deb && rm /tmp/chrome.deb
fi

# ---- Caddy
if ! command -v caddy >/dev/null; then
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update && apt-get install -y caddy
fi

# ---- the server
id tpr >/dev/null 2>&1 || useradd --system --home /srv/tpr --shell /usr/sbin/nologin tpr
mkdir -p /srv/tpr/db /srv/tpr/papers
git config --system --add safe.directory /srv/tpr/repo
if [ -d /srv/tpr/repo/.git ]; then
  git -C /srv/tpr/repo pull --ff-only
else
  git clone --depth 1 --filter=blob:none --sparse "$REPO" /srv/tpr/repo
  git -C /srv/tpr/repo sparse-checkout set tools/claude_extension
fi
if [ ! -f /srv/tpr/db/tipitaka_pali.db ]; then
  curl -fL --retry 3 "$DB_URL" | zstd -d | tar -C /srv/tpr/db -xf -
fi
chown -R tpr:tpr /srv/tpr

cat > /etc/systemd/system/tpr.service <<EOF
[Unit]
Description=TPR Research web server
After=network.target

[Service]
User=tpr
WorkingDirectory=/srv/tpr/repo/tools/claude_extension/server
ExecStart=/usr/bin/node index.js
Environment=TPR_WEB=1
Environment=TPR_DB_DIR=/srv/tpr/db
Environment=TPR_PAPERS_DIR=/srv/tpr/papers
Environment=TPR_PUBLIC_URL=https://$DOMAIN
Environment=PORT=8787
Restart=always
RestartSec=5
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/srv/tpr/papers /tmp
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/caddy/Caddyfile <<EOF
$DOMAIN {
  encode gzip
  reverse_proxy 127.0.0.1:8787 {
    header_up X-Forwarded-For {remote_host}
  }
}
EOF

systemctl daemon-reload
systemctl enable --now tpr
systemctl restart tpr
systemctl reload caddy || systemctl restart caddy
sleep 2
curl -s http://127.0.0.1:8787/ && echo "Set up. Test: https://$DOMAIN/mcp"
