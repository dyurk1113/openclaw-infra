# OpenClaw Infrastructure

Personal OpenClaw AI agent setup. No sensitive data — privacy requirements are low.

## GCP Setup

- **Project**: `gen-lang-client-0279759260` (Dominic-Default)
- **Region/Zone**: `us-central1-a`
- **Instance**: `openclaw` — e2-medium Spot VM, IP `136.111.143.112`
- **SSH**: `gcloud compute ssh openclaw --zone us-central1-a --project gen-lang-client-0279759260`
- **Logs**: `gcloud compute ssh openclaw --zone us-central1-a -- journalctl -u openclaw -f`
- **Startup log**: `/var/log/openclaw-startup.log`
- **VM service account**: `openclaw-vm@gen-lang-client-0279759260.iam.gserviceaccount.com`

Other Cloud Run services in same project: `caltrain-helper`, `sales-checker` (both us-central1).

## 1Password Integration

- **Vault**: `OpenClaw` (ID: `ow4xie7vfuy7pazhnpsvjukb2i`) — stores passwords/logins
- **SA Token**: stored in GCP Secret Manager as `op-sa-token-claw`; also in 1Password Shared vault as "Service Account Auth Token: Claw"
- **Local usage**: `op run --env-file .env -- <command>`
- **On VM**: SA token pulled from Secret Manager at startup, injected via `op run`

### Credentials in OpenClaw vault
- `OpenRouter` — login + API key (OpenClaw Key: `sk-or-v1-...`)

## LLM Provider

- **Provider**: OpenRouter (`openrouter/auto` model routing)
- **Account**: dominicyurk@gmail.com
- **Model strategy**: auto-routing — cheap models for simple tasks, escalates as needed

## Repo on VM

The VM clones this repo at startup for custom code. Path: `/home/openclaw/pi_repo`.

## Spot VM Notes

VM uses SPOT provisioning — can be preempted occasionally (rare in us-central1).
OpenClaw systemd service is set to restart on failure and enabled on boot, so it recovers automatically.

## WhatsApp Integration

Uses OpenClaw's native Baileys-based WhatsApp channel (no Twilio needed for messaging).
- `dmPolicy: allowlist` — only `+18176929089` can message the agent
- QR linking is a one-time manual step (see below)

## Files

- `startup.sh` — VM startup script (installs Node 22, op CLI, OpenClaw; pulls creds from 1Password)
- `openclaw.json` — OpenClaw config (model, WhatsApp channel policy)
- `.env` — `op://` references for local dev use with `op run`

## Gateway Access

Gateway binds to loopback only (`127.0.0.1:18789`). Access via SSH tunnel:
```bash
gcloud compute ssh openclaw --zone us-central1-a --project gen-lang-client-0279759260 -- -L 18789:127.0.0.1:18789
```
Then open `http://127.0.0.1:18789/` in browser. Token stored in 1Password OpenClaw vault → "OpenClaw Gateway".

Onboarding was done interactively with `openclaw onboard`. Config is now managed by OpenClaw — do NOT manually overwrite `openclaw.json` without using `openclaw config set` or it will fail metadata checks.

## First-time WhatsApp setup (one-time, requires interactive TTY)

```bash
gcloud compute ssh openclaw --zone us-central1-a --project gen-lang-client-0279759260
# Then on the VM:
HOME=/home/openclaw openclaw channels login --channel whatsapp
# Scan QR with WhatsApp: Settings > Linked Devices > Link a Device
sudo systemctl start openclaw
sudo journalctl -u openclaw -f
```

## Setup notes / lessons learned

- **Always use `openclaw onboard` interactively** — do NOT manually craft openclaw.json; it requires metadata fields only onboard sets correctly
- Onboarding ran as `dyurk` (SSH user) → all config/sessions live in `/home/dyurk/.openclaw/`, systemd service must use `User=dyurk`
- `channels login` requires root — run as root with `HOME=/home/dyurk`
- `.openclaw/` directory must be writable by root for login temp files
- WhatsApp plugin is bundled: `/usr/lib/node_modules/openclaw/dist/extensions/whatsapp`
- op CLI installed via `.deb`: `https://downloads.1password.com/linux/debian/amd64/stable/1password-cli-amd64-latest.deb`
- Gateway token stored in 1Password OpenClaw vault → "OpenClaw Gateway"
