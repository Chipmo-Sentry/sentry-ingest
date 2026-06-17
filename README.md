# sentry-ingest

The live-video plane of **Chipmo Sentry**. A thin, config-driven wrapper around
**[MediaMTX](https://github.com/bluenviron/mediamtx)** (a Go media server) plus a PowerShell ops kit for
running it — and its siblings — as services on the AI host.

MediaMTX is the **single fan-out point**: every camera is ingested exactly once, then served many ways —
`sentry-ai` pulls RTSP for inference, browsers play WHEP/WHS, and breach clips are cut from its recordings.

> **Never runs on Railway.** WebRTC/WHEP needs UDP + a reachable public IP, which an HTTP-first PaaS can't
> provide. This runs on the GPU host (Predator laptop today, a public GPU VPS at scale) — exposed via a
> Cloudflare Tunnel for HLS, or a direct public IP for full WebRTC ([ADR-0016](../docs/07-DECISIONS.md)).

---

## Two topologies

| Config | Mode | Where | What |
|---|---|---|---|
| `mediamtx.local.yml` | **pull** | dev laptop on the camera LAN | MediaMTX pulls RTSP straight from the 3 cameras (static paths) |
| `mediamtx.cloud.yml` | **publish** | public GPU VPS | store agents **push** (RTSP/WHIP); the backend creates paths dynamically |

The whole system flips between them with one backend env var (`AGENT_STREAM_PUSH_URL`): unset = LAN pull,
set = agents push to a central relay.

### Ports

| Port | Proto | Purpose |
|---|---|---|
| 8554 | RTSP (TCP) | agent publish / `sentry-ai` pull |
| 8888 | HTTP | HLS (fallback playback) |
| 8889 | HTTP | WHEP (WebRTC signalling) |
| 8189 | UDP+TCP | WebRTC media (ICE) |
| 9997 | HTTP | control API (backend adds/removes camera paths) |

### Security & recording

- **Auth** — `authMethod: http` points every read/publish/api action at the backend's
  `/api/v1/internal/mediamtx-auth`, which validates a stream token, publish credentials, or a shared
  secret. CORS is scoped to the frontend origin.
- **Recording** — `pathDefaults` records fmp4 (1 s parts, 60 s segments) with a retention window (24 h
  cloud / 2 h dev). These segments are what `sentry-ai`'s `cut-verify` slices for live-breach clips (L5).

---

## Quick start (local / dev)

```powershell
# 1. Download the MediaMTX binary into bin/ (gitignored). See the MediaMTX releases page.
# 2. Point a config at your cameras
Copy-Item mediamtx.local.yml mediamtx.yml      # edit camera IPs + credentials
# 3. Run it
.\bin\mediamtx.exe mediamtx.yml
```

Verify: the log shows each camera path `ready=true`; HLS serves at `http://localhost:8888/<path>/`,
WHEP at `http://localhost:8889/<path>/`, and the control API answers on `:9997`. A synthetic `test` path is
included so you can verify the transport without cameras on the LAN.

## Quick start (cloud / VPS)

```bash
cp .env.example .env       # MTX_PUBLIC_HOST, MTX_ALLOW_ORIGIN, MTX_PUBLISH_*, MTX_API_*, MTX_AUTH_URL
docker compose up -d       # bluenviron/mediamtx, network_mode: host, mediamtx.cloud.yml
```

`docker-compose.yml` runs with `network_mode: host` (real IP + UDP for ICE) and mounts the cloud config
read-only plus a `recordings/` volume. Full topology + the backend env vars that pair with it are in
**[DEPLOY.md](DEPLOY.md)**.

---

## Layout

```
mediamtx.local.yml    — dev pull config (3 LAN cameras)
mediamtx.cloud.yml    — VPS publish config (dynamic paths, http auth)
mediamtx.yml.example  — annotated template
docker-compose.yml    — VPS deployment
DEPLOY.md             — end-to-end topology + env reference
bin/mediamtx.exe      — the Go binary (download separately; gitignored)
predator/             — PowerShell ops kit (see below)
recordings/           — fmp4 segments (gitignored)
```

### Predator ops kit (`predator/`)

PowerShell scripts that run the whole AI host — **ollama → ingest (MediaMTX) → sentry-ai → cloudflared
tunnel** — as managed processes or Windows services on the "Predator" laptop:

- `predator.ps1` — start / stop / restart / status / health / logs for one or all components.
- `install-services.ps1` / `uninstall-services.ps1` — register each as an NSSM Windows service
  (`ChipmoSentry-*`), auto-restart on crash, logs to `predator/logs/`.
- `predator.config.ps1` — shared paths, ports, tunnel name, and component order.

> This kit is the manual/dev path. The **production** path is the one-installer `ChipmoSentryAi-Setup.exe`
> in [sentry-ai](https://github.com/Chipmo-Sentry/sentry-ai)`/installer/`, which sets the same services up
> from a wizard.

---

## Related repos

- [sentry-ai](https://github.com/Chipmo-Sentry/sentry-ai) — pulls RTSP from here for inference (co-located)
- [sentry-agent-pc](https://github.com/Chipmo-Sentry/sentry-agent-pc) — pushes camera streams here (cloud mode)
- [sentry-backend](https://github.com/Chipmo-Sentry/sentry-backend) — manages paths via the control API + auth hook

Platform overview: [Sentry-v.3 README](../README.md). Camera-bring-up checklist:
[docs/16-CAMERA-TEST-CHECKLIST.md](../docs/16-CAMERA-TEST-CHECKLIST.md).
