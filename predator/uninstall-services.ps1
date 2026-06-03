<#
.SYNOPSIS
  Stop + remove the Predator NSSM services. Run ELEVATED.
.EXAMPLE
  .\uninstall-services.ps1
  .\uninstall-services.ps1 -Component ai
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('all', 'ollama', 'ingest', 'ai', 'tunnel')]
    [string]$Component = 'all'
)

. "$PSScriptRoot\predator.config.ps1"
$cfg = $PredatorConfig

$nssm = $cfg.NssmExe
if (-not (Test-Path $nssm)) {
    $cmd = Get-Command 'nssm.exe' -ErrorAction SilentlyContinue
    if ($cmd) { $nssm = $cmd.Source } else { Write-Error "nssm.exe not found."; return }
}

$targets = if ($Component -eq 'all') { $PredatorComponents } else { @($Component) }
foreach ($name in $targets) {
    $svc = "$($cfg.ServicePrefix)$name"
    if ($PSCmdlet.ShouldProcess($svc, "nssm remove")) {
        & $nssm stop $svc
        & $nssm remove $svc confirm
        Write-Host "  removed $svc" -ForegroundColor Green
    }
}
