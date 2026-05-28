# sentry-ingest

> Live video ingest + rolling buffer + threshold-breach clip cut.
> M1 (current): MediaMTX standalone binary on dev laptop, RTSP pull from 3 LAN cameras.
> M2: Docker + MediaMTX on Hetzner VPS + thin Python control plane + WHIP push from sentry-agent-pc.

## M1 quickstart (Phase L0)

```powershell
# 0. Download MediaMTX binary (one-time, ~25 MB) — gitignored
$rel = Invoke-RestMethod "https://api.github.com/repos/bluenviron/mediamtx/releases/latest"
$url = ($rel.assets | Where-Object name -match "windows_amd64\.zip$").browser_download_url
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest $url -OutFile bin.zip
Expand-Archive bin.zip -DestinationPath bin -Force
Remove-Item bin.zip, bin\mediamtx.yml  # remove bundled default config

# 1. Copy template, fill camera credentials — never commit this file
Copy-Item mediamtx.yml.example mediamtx.yml
notepad mediamtx.yml
# Replace <HIK_USER>/<HIK_PASS>/<HIK_IP> + <UNV_*> placeholders.
# Password-д @#:* зэрэг тусгай тэмдэг бий бол URL-encode (жнь * → %2A).

# 2. Start MediaMTX (foreground, Ctrl+C to stop)
.\bin\mediamtx.exe .\mediamtx.yml

# 3. Өөр терминалаас — RTSP source connect эсэхийг log-аас ажиглах
Get-Content .\mediamtx.log -Tail 30 -Wait
# Хүлээх log:
#   INF [path cam1_hik] [RTSP source] started
#   INF [path cam1_hik] stream is available and online, 1 track (H264)

# 4. Live API summary
Invoke-RestMethod http://127.0.0.1:9997/v3/paths/list | Select-Object -Expand items |
  Select-Object name,ready,@{N='codec';E={$_.tracks2[0].codec}},bytesReceived |
  Format-Table -AutoSize
```

## Browser playback verify

| Кам | WebRTC (low-latency ~1s) | HLS (compat ~3-5s) |
|---|---|---|
| Hikvision | http://localhost:8889/cam1_hik | http://localhost:8888/cam1_hik/index.m3u8 |
| UNV (H.264 codec шаардлагатай) | http://localhost:8889/cam2_unv | http://localhost:8888/cam2_unv/index.m3u8 |

WebRTC URL-ыг Chrome-д шууд нээж WHEP playback харж болно (MediaMTX built-in test page).

> ⚠ **Skyworth ZHCSDB6 dropped 2026-05-28** — P2P-only consumer firmware (Tuya/iCSee-style cloud), no documented RTSP. Production pilots must use standard RTSP cameras (Hikvision/Dahua/UNV/Imou). См. mediamtx.yml comment + docs/14-LIVE-PIPELINE-PLAN.md §1.1.

## Ports

| Port | Protocol | Purpose |
|---|---|---|
| 8554 | RTSP | Internal — sentry-ai live worker subscribes (Phase L2) |
| 8888 | HTTP | HLS playback for browser |
| 8889 | HTTP | WHEP signaling for WebRTC |
| 8189 | UDP | WebRTC media (ICE) |
| 9997 | HTTP | REST API (live status, used by L5 clip cut control) |

## Recordings

`./recordings/<cam_path>/YYYY-MM-DD_HH-MM-SS-*` — fmp4, 60-sec segments, auto-delete after 24h.
Used by L5 threshold-breach clip cut endpoint.

## Tools

`./bin/mediamtx.exe` — MediaMTX v1.18.2 Windows amd64 binary. Gitignored — re-download via [docs/14-LIVE-PIPELINE-PLAN.md](../docs/14-LIVE-PIPELINE-PLAN.md).

## See also

- [docs/14-LIVE-PIPELINE-PLAN.md](../docs/14-LIVE-PIPELINE-PLAN.md) — full M1-LIVE build plan
- [docs/07-DECISIONS.md ADR-0014](../docs/07-DECISIONS.md) — M1 live-first pivot rationale
