# Predator control kit — shared configuration.
# Dot-sourced by predator.ps1 / install-services.ps1. Edit paths to match this
# machine. All four components connect OUT to the Railway-hosted backend.

$here = $PSScriptRoot                                   # ...\sentry-ingest\predator
$ingestRoot = Split-Path -Parent $here                 # ...\sentry-ingest
$repoRoot = Split-Path -Parent $ingestRoot             # ...\Sentry-v.3

$PredatorConfig = @{
    # --- Repo / binary paths -------------------------------------------------
    RepoRoot       = $repoRoot
    SentryAiPath   = Join-Path $repoRoot 'sentry-ai'
    IngestPath     = $ingestRoot
    MediaMtxExe    = Join-Path $ingestRoot 'bin\mediamtx.exe'
    MediaMtxConfig = Join-Path $ingestRoot 'mediamtx.yml'

    # `cloudflared` / `ollama` / `uv` are expected on PATH. Override with full
    # paths here if they are not.
    CloudflaredExe = 'cloudflared'
    OllamaExe      = 'ollama'
    UvExe          = 'uv'

    # --- Service / runtime settings -----------------------------------------
    TunnelName     = 'sentry-ingest'   # `cloudflared tunnel create <name>`
    AiHost         = '127.0.0.1'
    AiPort         = 8001
    OllamaPort     = 11434
    MediaMtxApiPort = 9997
    MediaMtxHlsPort = 8888

    # --- Where this kit writes PID + log files ------------------------------
    RunDir = Join-Path $here 'run'
    LogDir = Join-Path $here 'logs'

    # NSSM service name prefix (services appear as e.g. ChipmoSentry-ai).
    ServicePrefix = 'ChipmoSentry-'

    # nssm.exe location (for install-services.ps1). Drop nssm.exe next to this
    # kit, or point at an installed copy.
    NssmExe = Join-Path $here 'bin\nssm.exe'
}

# Component order matters: ollama + ingest first (ai depends on both reachable),
# tunnel last (exposes ingest once it is serving).
$PredatorComponents = @('ollama', 'ingest', 'ai', 'tunnel')
