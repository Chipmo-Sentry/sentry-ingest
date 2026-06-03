# Predator control kit

Run + manage the four "center" processes on the Predator laptop (RTX 4060)
that connect **out** to the Railway-hosted backend:

| Component | What | Already an exe? |
|---|---|---|
| `ollama` | VLM runtime (MiniCPM-V) | ✅ own installer |
| `ingest` | MediaMTX video fan-out (`bin/mediamtx.exe`) | ✅ single binary |
| `ai` | sentry-ai live worker + VLM verify (FastAPI/uvicorn) | ⚙ run via `uv` / NSSM service |
| `tunnel` | cloudflared — exposes ingest + ai to Railway | ✅ single binary |

> The **store-PC agent** (`ChipmoSentryAgent.exe`) is NOT part of this kit. It
> runs on the shop's PC to discover + register cameras into the backend. On
> Predator it only appears during local testing.

## Topology
```
[Store PC] ChipmoSentryAgent.exe ──pair + register cameras──> Railway backend
[Predator] ollama + MediaMTX + sentry-ai + cloudflared  ──(tunnel)──┐
[Railway]  backend / frontend / superadmin  <───────────────────────┘
backend ──> MediaMTX API (add camera paths) + ──> sentry-ai /v1/live/start
sentry-ai ──> backend /internal/live-metadata + /internal/alerts
```
The backend is the conductor: it reaches the Predator center **through the
cloudflared tunnel**, so the tunnel hostnames must be set in the backend env.

## Prerequisites (one-time, on Predator)
1. **Ollama** installed + model pulled: `ollama pull minicpm-v:8b`
2. **uv** installed (for sentry-ai): https://docs.astral.sh/uv/ , then in
   `..\..\sentry-ai`: `uv sync`
3. **MediaMTX** binary present at `..\bin\mediamtx.exe` (already in repo)
4. **cloudflared** installed + on PATH: https://github.com/cloudflare/cloudflared
5. **nssm.exe** (only for service install): https://nssm.cc → drop at
   `predator\bin\nssm.exe`

## Configure
1. Edit `predator.config.ps1` if any path/binary differs on this machine.
2. `copy config\sentry-ai.env.example ..\..\sentry-ai\.env` and fill
   `SENTRY_BACKEND_URL` + `SENTRY_BACKEND_SERVICE_TOKEN`.
3. Set up the tunnel: `copy config\cloudflared.config.yml.example` to
   `%USERPROFILE%\.cloudflared\config.yml`, fill the tunnel UUID + credentials,
   and run the `tunnel create` / `route dns` commands in that file's header.

### Railway backend env to set (so it can drive this center)
| Env | Value |
|---|---|
| `SENTRY_AI_URL` | `https://ai.sentry.chipmo.mn` |
| `MEDIAMTX_API_URL` | `https://mtxapi.sentry.chipmo.mn` |
| `MEDIAMTX_API_USER` / `MEDIAMTX_API_PASS` | match MediaMTX `MTX_API_*` |
| `MEDIAMTX_RTSP_URL` | RTSP base sentry-ai pulls from (usually `rtsp://127.0.0.1:8554`) |
| `LIVE_METADATA_SHARED_SECRET` | **must equal** sentry-ai `SENTRY_BACKEND_SERVICE_TOKEN` |

Frontend: `NEXT_PUBLIC_MEDIAMTX_HLS_BASE=https://media.sentry.chipmo.mn`,
`NEXT_PUBLIC_MEDIAMTX_WHEP_BASE=https://whep.sentry.chipmo.mn`.

## Run — ad-hoc (no admin)
```powershell
.\predator.ps1 start all      # ollama -> ingest -> ai -> tunnel
.\predator.ps1 status
.\predator.ps1 health         # HTTP probes each component
.\predator.ps1 logs ai        # tail sentry-ai stdout/stderr
.\predator.ps1 restart ai
.\predator.ps1 stop all
```
PIDs live in `predator\run\`, logs in `predator\logs\`.

## Run — as Windows services (boot-start + auto-restart)
```powershell
# Elevated PowerShell, with nssm.exe in place:
.\install-services.ps1            # install + start ChipmoSentry-<component>
.\install-services.ps1 -WhatIf    # preview the nssm commands
# manage via services.msc or:  nssm start/stop ChipmoSentry-ai
.\uninstall-services.ps1          # stop + remove all four
```

## Verify the chain
1. `.\predator.ps1 health` → all four OK (`ai` shows `/healthz`,
   `ingest` shows the MediaMTX API).
2. Register a camera (store-PC agent or frontend) → backend calls MediaMTX +
   sentry-ai; within ~60s the live worker starts.
3. Open the deployed frontend `/live` → video + AI bbox overlay.

## ⚠ Known gap — L5 clip cut (live breach → saved clip)
On a threshold breach the **backend** cuts the clip from
`MEDIAMTX_RECORDINGS_DIR`. The Railway backend cannot read Predator's local
recordings folder, so live-breach clip saving won't work in this split
topology until the cut is moved to a Predator-side ingest control plane
(sentry-ingest `/v1/cut`, TODO I5) or done by sentry-ai. Live view + alerts
still work; only the saved-clip-on-breach step is affected.
