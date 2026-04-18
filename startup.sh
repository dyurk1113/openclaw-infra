#!/bin/bash
set -euo pipefail
exec > /var/log/openclaw-startup.log 2>&1

echo "=== OpenClaw startup $(date) ==="

# ── 1. System deps ───────────────────────────────────────────────────────────
apt-get update -q
apt-get install -y -q curl unzip jq git

# ── 2. Node.js 22 ────────────────────────────────────────────────────────────
if ! node --version 2>/dev/null | grep -q "^v22"; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y -q nodejs
fi
echo "Node: $(node --version)"

# ── 3. 1Password CLI (arm64) ─────────────────────────────────────────────────
if ! command -v op &>/dev/null; then
  OP_VERSION=$(curl -s https://app-updates.agilebits.com/product_history/CLI2 \
    | grep -oP '(?<=<version>)[^<]+' | head -1)
  curl -sSfo /tmp/op.zip \
    "https://cache.agilebits.com/dist/1P/op2/pkg/${OP_VERSION}/op_linux_amd64_${OP_VERSION}.zip"
  unzip -o /tmp/op.zip -d /usr/local/bin/
  chmod +x /usr/local/bin/op
fi
echo "op: $(op --version)"

# ── 4. Pull 1Password SA token from Secret Manager ───────────────────────────
export OP_SERVICE_ACCOUNT_TOKEN=$(gcloud secrets versions access latest \
  --secret=op-sa-token-claw \
  --project=gen-lang-client-0279759260)

# Helper to read from 1Password
op_get() { OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN" op item get "$1" \
  --vault "OpenClaw" --fields "$2" --reveal; }

# ── 5. Install OpenClaw + WhatsApp plugin ────────────────────────────────────
npm install -g openclaw 2>&1 | tail -3
openclaw plugins install @openclaw/whatsapp 2>&1 | tail -3
echo "OpenClaw: $(openclaw --version)"

# ── 6. Create openclaw user ──────────────────────────────────────────────────
useradd -r -m -s /bin/bash openclaw 2>/dev/null || true
CLAW_HOME=/home/openclaw
mkdir -p "$CLAW_HOME/.openclaw"

# ── 7. Clone/update repo ─────────────────────────────────────────────────────
GITHUB_TOKEN=$(op_get "GitHub Token" credential)
REPO_DIR="$CLAW_HOME/pi_repo"
if [ -d "$REPO_DIR/.git" ]; then
  git -C "$REPO_DIR" pull --ff-only
else
  git clone "https://dyurk1113:${GITHUB_TOKEN}@github.com/dyurk1113/openclaw-infra.git" "$REPO_DIR"
fi

# ── 8. Write openclaw.json config ────────────────────────────────────────────
OPENROUTER_API_KEY=$(op_get "OpenRouter" "API Key")

cat > "$CLAW_HOME/.openclaw/openclaw.json" << EOF
{
  "model": "openrouter/auto",
  "provider": "openrouter",
  "apiKey": "${OPENROUTER_API_KEY}",
  "hostname": "openclaw-gcp",
  "channels": {
    "whatsapp": {
      "dmPolicy": "allowlist",
      "allowFrom": ["+18176929089"],
      "groupPolicy": "allowlist",
      "selfChatMode": true
    }
  }
}
EOF

# ── 9. Write .env for op run ─────────────────────────────────────────────────
GITHUB_TOKEN_VAL="$GITHUB_TOKEN"
cat > "$CLAW_HOME/.env" << EOF
OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
GITHUB_TOKEN=${GITHUB_TOKEN_VAL}
OP_SERVICE_ACCOUNT_TOKEN=${OP_SERVICE_ACCOUNT_TOKEN}
EOF
chmod 600 "$CLAW_HOME/.env"

# ── 10. Ownership ────────────────────────────────────────────────────────────
chown -R openclaw:openclaw "$CLAW_HOME"

# ── 11. Systemd service (gateway mode) ───────────────────────────────────────
cat > /etc/systemd/system/openclaw.service << 'EOF'
[Unit]
Description=OpenClaw AI Agent Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=openclaw
WorkingDirectory=/home/openclaw
EnvironmentFile=/home/openclaw/.env
ExecStart=/usr/bin/openclaw gateway
Restart=on-failure
RestartSec=15
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable openclaw

# Don't auto-start — WhatsApp QR link must be done first interactively
# Run: gcloud compute ssh openclaw-vm -- sudo -u openclaw openclaw channels login --channel whatsapp
# Then: sudo systemctl start openclaw

echo ""
echo "=== Setup complete $(date) ==="
echo "ACTION REQUIRED: SSH in and run WhatsApp QR linking:"
echo "  sudo -u openclaw openclaw channels login --channel whatsapp"
echo "  Then: sudo systemctl start openclaw"
