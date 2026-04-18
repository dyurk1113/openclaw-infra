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

## Files

- `startup.sh` — VM startup script (installs Node 22, op CLI, OpenClaw; pulls creds from 1Password)
- `.env` — `op://` references for local dev use with `op run`
