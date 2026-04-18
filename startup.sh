#!/bin/bash
set -euo pipefail
exec > /var/log/openclaw-startup.log 2>&1

echo "=== OpenClaw startup $(date) ==="

# ── 1. Install system deps ──────────────────────────────────────────────────
apt-get update -q
apt-get install -y -q curl unzip jq

# ── 2. Install Node.js 22 ───────────────────────────────────────────────────
if ! node --version 2>/dev/null | grep -q "^v22"; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y -q nodejs
fi
echo "Node: $(node --version)"

# ── 3. Install 1Password CLI ────────────────────────────────────────────────
if ! command -v op &>/dev/null; then
  OP_VERSION=$(curl -s https://app-updates.agilebits.com/product_history/CLI2 | grep -oP '(?<=<version>)[^<]+' | head -1)
  curl -sSfo /tmp/op.zip "https://cache.agilebits.com/dist/1P/op2/pkg/${OP_VERSION}/op_linux_arm64_${OP_VERSION}.zip"
  unzip -o /tmp/op.zip -d /usr/local/bin/
  chmod +x /usr/local/bin/op
fi
echo "op: $(op --version)"

# ── 4. Pull 1Password SA token from Secret Manager ──────────────────────────
export OP_SERVICE_ACCOUNT_TOKEN=$(gcloud secrets versions access latest \
  --secret=op-sa-token-claw \
  --project=gen-lang-client-0279759260)

# ── 5. Install OpenClaw ─────────────────────────────────────────────────────
if ! command -v openclaw &>/dev/null; then
  npm install -g openclaw
fi
echo "OpenClaw: $(openclaw --version 2>/dev/null || echo 'installed')"

# ── 6. Create openclaw user & dirs ──────────────────────────────────────────
useradd -r -m -s /bin/bash openclaw 2>/dev/null || true
mkdir -p /home/openclaw/.config/openclaw
chown -R openclaw:openclaw /home/openclaw

# ── 6b. Clone/update repo ────────────────────────────────────────────────────
apt-get install -y -q git
REPO_DIR=/home/openclaw/pi_repo
if [ -d "$REPO_DIR/.git" ]; then
  git -C "$REPO_DIR" pull --ff-only
else
  git clone https://github.com/dyurk1113/openclaw-infra.git "$REPO_DIR"
fi
chown -R openclaw:openclaw "$REPO_DIR"

# ── 7. Write openclaw config pulling from 1Password ─────────────────────────
OPENROUTER_API_KEY=$(OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN" \
  op item get "OpenRouter" --vault "OpenClaw" --fields "API Key" --reveal)

cat > /home/openclaw/.config/openclaw/config.json << EOF
{
  "provider": "openrouter",
  "model": "openrouter/auto",
  "apiKey": "${OPENROUTER_API_KEY}",
  "hostname": "openclaw-gcp"
}
EOF
chown openclaw:openclaw /home/openclaw/.config/openclaw/config.json
chmod 600 /home/openclaw/.config/openclaw/config.json

# ── 8. Write systemd service ─────────────────────────────────────────────────
cat > /etc/systemd/system/openclaw.service << 'EOF'
[Unit]
Description=OpenClaw AI Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=openclaw
WorkingDirectory=/home/openclaw
ExecStart=/usr/bin/openclaw start
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable openclaw
systemctl start openclaw

echo "=== OpenClaw startup complete $(date) ==="
