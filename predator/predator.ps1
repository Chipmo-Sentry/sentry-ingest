<#
.SYNOPSIS
  Start / stop / inspect the four Predator "center" processes that connect to
  the Railway-hosted backend: ollama, ingest (MediaMTX), ai (sentry-ai),
  tunnel (cloudflared).

.DESCRIPTION
  Ad-hoc process manager — no admin or service install required. Each component
  runs as a background process; PIDs + logs are tracked under predator\run and
  predator\logs. For boot-start + auto-restart, use install-services.ps1 (NSSM).

.EXAMPLE
  .\predator.ps1 start all
  .\predator.ps1 status
  .\predator.ps1 health
  .\predator.ps1 logs ai
  .\predator.ps1 stop ingest
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('start', 'stop', 'restart', 'status', 'health', 'logs')]
    [string]$Action = 'status',

    [Parameter(Position = 1)]
    [ValidateSet('all', 'ollama', 'ingest', 'ai', 'tunnel')]
    [string]$Component = 'all'
)

. "$PSScriptRoot\predator.config.ps1"

$cfg = $PredatorConfig
New-Item -ItemType Directory -Force -Path $cfg.RunDir, $cfg.LogDir | Out-Null

# ── Per-component launch definition ─────────────────────────────────────────
function Get-Spec([string]$name) {
    switch ($name) {
        'ollama' {
            return @{ File = $cfg.OllamaExe; Args = @('serve'); Wd = $cfg.RepoRoot }
        }
        'ingest' {
            return @{ File = $cfg.MediaMtxExe; Args = @($cfg.MediaMtxConfig); Wd = $cfg.IngestPath }
        }
        'ai' {
            return @{
                File = $cfg.UvExe
                Args = @('run', 'uvicorn', 'sentry_ai.main:app', '--host', $cfg.AiHost, '--port', "$($cfg.AiPort)")
                Wd   = $cfg.SentryAiPath
            }
        }
        'tunnel' {
            return @{ File = $cfg.CloudflaredExe; Args = @('tunnel', 'run', $cfg.TunnelName); Wd = $cfg.RepoRoot }
        }
    }
}

function Resolve-Components([string]$c) {
    if ($c -eq 'all') { return $PredatorComponents }
    return @($c)
}

function Get-PidFile([string]$name) { Join-Path $cfg.RunDir "$name.pid" }

function Get-RunningProc([string]$name) {
    $pf = Get-PidFile $name
    if (-not (Test-Path $pf)) { return $null }
    $procId = (Get-Content $pf -ErrorAction SilentlyContinue | Select-Object -First 1)
    if (-not $procId) { return $null }
    $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if ($null -eq $p) { return $null }
    return $p
}

function Start-One([string]$name) {
    $existing = Get-RunningProc $name
    if ($null -ne $existing) {
        Write-Host ("  {0,-8} already running (PID {1})" -f $name, $existing.Id) -ForegroundColor Yellow
        return
    }
    $spec = Get-Spec $name
    $outLog = Join-Path $cfg.LogDir "$name.out.log"
    $errLog = Join-Path $cfg.LogDir "$name.err.log"
    try {
        $p = Start-Process -FilePath $spec.File -ArgumentList $spec.Args `
            -WorkingDirectory $spec.Wd -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $outLog -RedirectStandardError $errLog
        Set-Content -Path (Get-PidFile $name) -Value $p.Id -Encoding ascii
        Write-Host ("  {0,-8} started (PID {1})" -f $name, $p.Id) -ForegroundColor Green
    }
    catch {
        Write-Host ("  {0,-8} FAILED to start: {1}" -f $name, $_.Exception.Message) -ForegroundColor Red
    }
}

function Stop-One([string]$name) {
    $p = Get-RunningProc $name
    if ($null -eq $p) {
        Write-Host ("  {0,-8} not running" -f $name) -ForegroundColor DarkGray
    }
    else {
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
            Write-Host ("  {0,-8} stopped (PID {1})" -f $name, $p.Id) -ForegroundColor Green
        }
        catch {
            Write-Host ("  {0,-8} stop failed: {1}" -f $name, $_.Exception.Message) -ForegroundColor Red
        }
    }
    Remove-Item (Get-PidFile $name) -ErrorAction SilentlyContinue
}

function Test-Endpoint([string]$url) {
    try {
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3
        return ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500)
    }
    catch {
        # A 4xx still means the port is listening — only connection errors fail.
        if ($_.Exception.Response) { return $true }
        return $false
    }
}

function Get-HealthUrl([string]$name) {
    switch ($name) {
        'ollama' { return "http://127.0.0.1:$($cfg.OllamaPort)/api/tags" }
        'ingest' { return "http://127.0.0.1:$($cfg.MediaMtxApiPort)/v3/config/global/get" }
        'ai'     { return "http://$($cfg.AiHost):$($cfg.AiPort)/healthz" }
        'tunnel' { return $null }   # no local endpoint — process liveness only
    }
}

function Show-Status {
    Write-Host "Predator components:" -ForegroundColor Cyan
    foreach ($name in $PredatorComponents) {
        $p = Get-RunningProc $name
        if ($null -ne $p) {
            Write-Host ("  {0,-8} RUNNING  PID {1}" -f $name, $p.Id) -ForegroundColor Green
        }
        else {
            Write-Host ("  {0,-8} stopped" -f $name) -ForegroundColor DarkGray
        }
    }
}

function Show-Health {
    Write-Host "Health checks:" -ForegroundColor Cyan
    foreach ($name in $PredatorComponents) {
        $url = Get-HealthUrl $name
        if ($null -eq $url) {
            $p = Get-RunningProc $name
            $ok = ($null -ne $p)
            $detail = if ($ok) { "process up (no HTTP probe)" } else { "stopped" }
        }
        else {
            $ok = Test-Endpoint $url
            $detail = $url
        }
        $tag = if ($ok) { "OK  " } else { "DOWN" }
        $color = if ($ok) { 'Green' } else { 'Red' }
        Write-Host ("  {0,-8} {1}  {2}" -f $name, $tag, $detail) -ForegroundColor $color
    }
}

function Show-Logs([string]$name) {
    if ($name -eq 'all') {
        Write-Host "Pick one component for logs, e.g. .\predator.ps1 logs ai" -ForegroundColor Yellow
        return
    }
    $outLog = Join-Path $cfg.LogDir "$name.out.log"
    $errLog = Join-Path $cfg.LogDir "$name.err.log"
    foreach ($f in @($errLog, $outLog)) {
        if (Test-Path $f) {
            Write-Host "==== $f (last 30) ====" -ForegroundColor Cyan
            Get-Content $f -Tail 30
        }
    }
}

# ── Dispatch ────────────────────────────────────────────────────────────────
$targets = Resolve-Components $Component

switch ($Action) {
    'start' { foreach ($t in $targets) { Start-One $t } }
    'stop' { foreach ($t in @($targets)[($targets.Count - 1)..0]) { Stop-One $t } }
    'restart' {
        foreach ($t in @($targets)[($targets.Count - 1)..0]) { Stop-One $t }
        Start-Sleep -Seconds 1
        foreach ($t in $targets) { Start-One $t }
    }
    'status' { Show-Status }
    'health' { Show-Health }
    'logs' { Show-Logs $Component }
}
