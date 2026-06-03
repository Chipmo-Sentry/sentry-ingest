<#
.SYNOPSIS
  Install the four Predator components as Windows services via NSSM
  (boot-start + auto-restart on crash). Run from an ELEVATED PowerShell.

.DESCRIPTION
  Wraps ollama / MediaMTX / sentry-ai / cloudflared as services named
  <ServicePrefix><component> (e.g. ChipmoSentry-ai). NSSM redirects each
  service's stdout/stderr to predator\logs and restarts it on exit.

  Requires nssm.exe (https://nssm.cc). Place it at the path in
  predator.config.ps1 (NssmExe) or on PATH.

.EXAMPLE
  # Elevated PowerShell:
  .\install-services.ps1            # install + start all four
  .\install-services.ps1 -WhatIf    # print the nssm commands only
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('all', 'ollama', 'ingest', 'ai', 'tunnel')]
    [string]$Component = 'all'
)

. "$PSScriptRoot\predator.config.ps1"
$cfg = $PredatorConfig
New-Item -ItemType Directory -Force -Path $cfg.LogDir | Out-Null

# Resolve nssm.exe (config path first, then PATH).
$nssm = $cfg.NssmExe
if (-not (Test-Path $nssm)) {
    $cmd = Get-Command 'nssm.exe' -ErrorAction SilentlyContinue
    if ($cmd) { $nssm = $cmd.Source }
}
if (-not (Test-Path $nssm) -and -not (Get-Command 'nssm.exe' -ErrorAction SilentlyContinue)) {
    Write-Error "nssm.exe not found. Download from https://nssm.cc and place it at '$($cfg.NssmExe)' (or on PATH)."
    return
}

function Resolve-Exe([string]$file) {
    if (Test-Path $file) { return (Resolve-Path $file).Path }
    $c = Get-Command $file -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    throw "Executable '$file' not found (not a path, not on PATH)."
}

function Get-Spec([string]$name) {
    switch ($name) {
        'ollama' { return @{ File = $cfg.OllamaExe; Args = 'serve'; Wd = $cfg.RepoRoot } }
        'ingest' { return @{ File = $cfg.MediaMtxExe; Args = ('"' + $cfg.MediaMtxConfig + '"'); Wd = $cfg.IngestPath } }
        'ai' {
            return @{
                File = $cfg.UvExe
                Args = "run uvicorn sentry_ai.main:app --host $($cfg.AiHost) --port $($cfg.AiPort)"
                Wd   = $cfg.SentryAiPath
            }
        }
        'tunnel' { return @{ File = $cfg.CloudflaredExe; Args = "tunnel run $($cfg.TunnelName)"; Wd = $cfg.RepoRoot } }
    }
}

function Install-One([string]$name) {
    $svc = "$($cfg.ServicePrefix)$name"
    $spec = Get-Spec $name
    $exe = Resolve-Exe $spec.File
    $out = Join-Path $cfg.LogDir "$name.out.log"
    $err = Join-Path $cfg.LogDir "$name.err.log"

    if ($PSCmdlet.ShouldProcess($svc, "nssm install")) {
        & $nssm install $svc $exe $spec.Args
        & $nssm set $svc AppDirectory $spec.Wd
        & $nssm set $svc AppStdout $out
        & $nssm set $svc AppStderr $err
        & $nssm set $svc Start SERVICE_AUTO_START
        & $nssm set $svc AppExit Default Restart
        & $nssm set $svc AppRestartDelay 5000
        & $nssm set $svc DisplayName "Chipmo Sentry - $name (Predator)"
        & $nssm start $svc
        Write-Host "  installed + started $svc" -ForegroundColor Green
    }
    else {
        Write-Host ("  [WhatIf] nssm install {0} {1} {2}" -f $svc, $exe, $spec.Args) -ForegroundColor DarkGray
    }
}

$targets = if ($Component -eq 'all') { $PredatorComponents } else { @($Component) }
Write-Host "Installing services via $nssm" -ForegroundColor Cyan
foreach ($t in $targets) { Install-One $t }
Write-Host ("Done. Manage with services.msc, or: nssm start/stop {0}ai" -f $cfg.ServicePrefix) -ForegroundColor Cyan
