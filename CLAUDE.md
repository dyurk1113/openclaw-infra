# OpenClaw Infrastructure

Personal OpenClaw AI agent setup. No sensitive data — privacy requirements are low.

## GCP Setup

- **Project**: `gen-lang-client-0279759260` (Dominic-Default)
- **Region/Zone**: `us-central1-a`
- **Instance**: `openclaw` — e2-medium Spot VM, IP `136.111.143.112`
- **SSH**: `gcloud compute ssh openclaw --zone us-central1-a --project gen-lang-client-0279759260`
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
- `OpenClaw Gateway` — web UI auth token (stored after onboarding)

## LLM Provider

- **Provider**: OpenRouter (`openrouter/auto` model routing)
- **Account**: dominicyurk@gmail.com
- **Model strategy**: auto-routing — cheap models for simple tasks, escalates as needed
- **API key location on VM**: `/home/dyurk/.openclaw/agents/main/agent/auth-profiles.json`

## Repo on VM

The VM clones this repo at startup for custom code. Path: `/home/dyurk/pi_repo`.

## Spot VM Notes

VM uses SPOT provisioning — can be preempted occasionally (rare in us-central1).
OpenClaw user-level systemd service is enabled on boot (`loginctl enable-linger dyurk`), so it recovers automatically.

## WhatsApp Integration

Uses OpenClaw's native Baileys-based WhatsApp channel (no Twilio needed for messaging).
- `dmPolicy: allowlist` — only `+18176929089` can message the agent
- QR linking is a one-time manual step (see below)

## Files

- `startup.sh` — VM startup script (installs Node 22, op CLI, OpenClaw; pulls creds from 1Password)
- `openclaw.json` — reference config only (actual config managed by openclaw on the VM)
- `.env` — `op://` references for local dev use with `op run`

## Gateway Management (use these, not manual systemctl)

OpenClaw manages its own **user-level** systemd service at `~/.config/systemd/user/openclaw-gateway.service`.
Always use openclaw's built-in commands to manage the gateway:

```bash
HOME=/home/dyurk openclaw gateway status        # check if running
HOME=/home/dyurk openclaw gateway status --deep # full diagnostics
HOME=/home/dyurk openclaw gateway restart       # restart (official way)
HOME=/home/dyurk openclaw gateway stop          # stop
HOME=/home/dyurk openclaw gateway start         # start
HOME=/home/dyurk openclaw channels status --probe   # check WhatsApp connected
HOME=/home/dyurk openclaw doctor                # diagnose all issues
HOME=/home/dyurk openclaw doctor --fix          # auto-fix what it can
HOME=/home/dyurk openclaw logs --follow         # tail logs
```

**Never use `sudo systemctl` to manage OpenClaw** — that's for the old system-level service which has been removed. The user service handles itself.

## Gateway Access (Web UI)

Gateway binds to loopback only (`127.0.0.1:18789`). Access via SSH tunnel:
```bash
gcloud compute ssh openclaw --zone us-central1-a --project gen-lang-client-0279759260 -- -L 18789:127.0.0.1:18789
```
Then open `http://127.0.0.1:18789/` in browser. Token in 1Password OpenClaw vault → "OpenClaw Gateway".

## Diagnosing Problems

**Always run `openclaw doctor` first before digging into logs or system files.** It catches:
- Missing config fields
- Stale state directories
- Auth / API key issues
- Orphaned processes / port conflicts
- Plugin dependency problems

Then read `/tmp/openclaw/openclaw-2026-XX-XX.log` for detailed per-request logs.

## First-time WhatsApp setup (one-time, requires interactive TTY)

```bash
gcloud compute ssh openclaw --zone us-central1-a --project gen-lang-client-0279759260
# Then on the VM:
sudo HOME=/home/dyurk openclaw channels login --channel whatsapp
# Scan QR with WhatsApp: Settings > Linked Devices > Link a Device
HOME=/home/dyurk openclaw gateway start
```

## Setup notes / lessons learned

- **Always use `openclaw onboard` interactively** — do NOT manually craft openclaw.json; it requires metadata fields only onboard sets correctly
- Onboarding ran as `dyurk` (SSH user) → all config/sessions live in `/home/dyurk/.openclaw/`
- **Use OpenClaw's user-level service, not a custom system service** — `openclaw gateway install --force` sets it up at `~/.config/systemd/user/openclaw-gateway.service`; enable linger with `sudo loginctl enable-linger dyurk`
- **Do NOT create a system-level `/etc/systemd/system/openclaw.service`** — it conflicts with the user service and spawns orphaned processes
- `channels login` requires root — run as `sudo HOME=/home/dyurk openclaw channels login --channel whatsapp`
- WhatsApp plugin is bundled: `/usr/lib/node_modules/openclaw/dist/extensions/whatsapp`
- op CLI installed via `.deb`: `https://downloads.1password.com/linux/debian/amd64/stable/1password-cli-amd64-latest.deb`
- **"gateway already running" / EADDRINUSE**: caused by orphaned `openclaw-gateway` child processes after improper stop. Fix: `openclaw gateway stop`, then if stuck, `openclaw gateway status --deep` to find PID, `kill <pid>`. Then `openclaw gateway start`.
- **"agent couldn't generate a response"**: check `openclaw doctor` first. Common causes: memory search enabled with no embedding provider configured (fix: `openclaw config set agents.defaults.memorySearch.enabled false`), or OpenRouter API key missing/out of credits.
- **SSH commands failing with exit 255**: usually a command in the chain returned non-zero (e.g. `pkill` with no matches). Run commands separately rather than chaining with `&&`.
- **Stale `/home/openclaw/.openclaw`**: old config from when openclaw user was used before onboarding. Doctor flags this but it doesn't need to be deleted — just ignored since active state is `/home/dyurk/.openclaw/`.
- Low-power VM optimization (set in service override at `~/.config/systemd/user/openclaw-gateway.service.d/override.conf`):
  ```
  NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache
  OPENCLAW_NO_RESPAWN=1
  ```
