# Chipmo Sentry — Live Pipeline Deployment

How the live, low-latency, AI-overlaid camera view is wired across services, and
how to deploy it. This is the cloud (publish) topology: stores connect over the
internet to a central sentry-ai.

```
┌─ Store LAN ───────────────┐        ┌─ Cloud ─────────────────────────────────┐
│ Cameras (Hik/UNV/…)       │        │  MediaMTX (this repo, on a VPS)          │
│   │ RTSP (LAN)            │ publish│   :8554 RTSP  ── pull ──▶ sentry-ai      │
│   ▼                       │  (TCP) │   :8889 WHEP ─┐           │ metadata     │
│ sentry-agent-pc ──────────┼───────▶│   :8888 HLS  ─┤           ▼              │
│  ffmpeg -c copy per cam   │        │               │      sentry-backend       │
└───────────────────────────┘        │               │      /ws/live/{path}     │
        ▲                             └───────────────┼──────────────────────────┘
        │ WHEP + WS                                   │
        └──────── agent-pc webview  ≡  web /live ◀────┘
```

**One source of truth:** MediaMTX is the single fan-out point. Each camera is
ingested once (store agent publishes it); sentry-ai reads it from MediaMTX (not
the camera), and browsers + the agent-pc webview play WebRTC from MediaMTX. The
AI overlay is metadata over a WebSocket, drawn client-side — so web and desktop
render identically.

## Where each service runs

| Service | Host | Why |
|---|---|---|
| sentry-backend | Railway | HTTP only — fits Railway. Already deployed pattern. |
| sentry-frontend | Railway / Vercel | Static + SSR HTTP. |
| **sentry-ingest (MediaMTX)** | **VPS with public IP (Hetzner)** | Needs raw TCP (RTSP :8554) + **UDP** (WebRTC :8189). PaaS like Railway don't expose UDP. |
| **sentry-ai** | **GPU host** (Hetzner GPU / RunPod / Lambda) | YOLO inference. Railway has no GPU. 2–4 cams可 run on CPU but GPU is recommended. |

> ⚠️ **Do not put MediaMTX on Railway.** WebRTC requires a publicly reachable
> UDP port and the host's real IP in ICE candidates; Railway provides neither.
> A cheap VPS with a public IP is the right home.

## 1. Deploy MediaMTX (sentry-ingest) on a VPS

```bash
# On the VPS (Ubuntu + Docker):
git clone https://github.com/Chipmo-Sentry/sentry-ingest && cd sentry-ingest
cp .env.example .env && nano .env          # set MTX_PUBLIC_HOST + secrets
docker compose up -d
```

Point DNS (e.g. `media.sentry.chipmo.mn`) at the VPS and open the firewall:

| Port | Proto | For |
|---|---|---|
| 8554 | tcp | RTSP — agents publish, sentry-ai pulls |
| 8889 | tcp | WHEP (WebRTC signaling) |
| 8189 | tcp+udp | WebRTC media |
| 8888 | tcp | HLS fallback |
| 9997 | tcp | Control API — **restrict to the backend's egress IP** |

## 2. Configure sentry-backend (Railway env)

| Env | Value | Effect |
|---|---|---|
| `MEDIAMTX_API_URL` | `http://media.sentry.chipmo.mn:9997` | Where to add/remove paths |
| `MEDIAMTX_API_USER` / `MEDIAMTX_API_PASS` | = `MTX_API_USER/PASS` | Control-API Basic auth |
| `MEDIAMTX_RTSP_URL` | `rtsp://media.sentry.chipmo.mn:8554` | What sentry-ai pulls |
| `AGENT_STREAM_PUSH_URL` | `rtsp://media.sentry.chipmo.mn:8554` | Turns on publish mode + tells agents where to push |
| `MEDIAMTX_PUBLISH_USER` / `MEDIAMTX_PUBLISH_PASS` | = `MTX_PUBLISH_USER/PASS` | Handed to agents via `/agent/stream-config` |
| `SENTRY_AI_URL` | `http://<sentry-ai-host>:8000` | Backend auto-starts the live worker on register |

Setting `AGENT_STREAM_PUSH_URL` flips MediaMTX paths to **publish mode** (no pull
`source`) and makes `GET /api/v1/agent/stream-config` return `push_enabled:true`.
Leave it unset for the local/on-LAN topology (MediaMTX pulls cameras directly).

## 3. Configure sentry-frontend (env)

| Env | Value |
|---|---|
| `NEXT_PUBLIC_MEDIAMTX_WHEP_BASE` | `https://media.sentry.chipmo.mn:8889` |
| `NEXT_PUBLIC_MEDIAMTX_HLS_BASE` | `https://media.sentry.chipmo.mn:8888` |
| `NEXT_PUBLIC_API_BASE_URL` | backend URL (for the `/ws/live` metadata) |

> For HTTPS pages, MediaMTX must be served over TLS (put Caddy/Nginx in front,
> or use MediaMTX's built-in certs) so the browser allows the WHEP fetch.

## 4. Configure sentry-agent-pc (per store)

Agents need nothing extra — they call `/agent/stream-config` after pairing,
learn the push URL + credentials, and run one `ffmpeg -c copy` relay per camera.
Set `FRONTEND_URL` (default `https://app.sentry.chipmo.mn`) so the **📺 Шууд харах**
webview loads the right `/live`.

## Caveats & honest limits

- **Skyworth ZHCSDB6** (and similar P2P/Tuya "AI Home Camera" units) are
  **not supported** — H.265-only, no RTSP service path, cloud-P2P only. Use
  standard ONVIF/RTSP cameras (Hikvision/Dahua/UNV/Imou). Other Skyworth models
  that expose ONVIF/RTSP work fine.
- **Read auth is open** in `mediamtx.cloud.yml` — anyone who knows a path slug
  can view it. Slugs are unguessable, but for real multi-tenant isolation add
  per-store read credentials (hardening TODO).
- **GPU for sentry-ai**: YOLO11n on 2–4 cams may run acceptably on CPU; a small
  GPU removes the FPS ceiling. Decide host based on store count.
- **Upload bandwidth**: each camera ≈ 2–4 Mbps up from the store. If a store's
  uplink is tight, publish the camera's sub-stream instead of the main stream.
