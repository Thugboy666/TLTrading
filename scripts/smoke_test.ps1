Remove-Item Env:PACKET_SIGNING_PRIVATE_KEY_BASE64 -ErrorAction SilentlyContinue
Remove-Item Env:PACKET_SIGNING_PUBLIC_KEY_BASE64 -ErrorAction SilentlyContinue
Write-Host "[step6] Signing env vars cleared for test session"

$repoRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot/_load_env.ps1"

if (-not $env:DATA_DIR) { $env:DATA_DIR = Join-Path $repoRoot "runtime/data" }
if (-not $env:LOG_DIR) { $env:LOG_DIR = Join-Path $repoRoot "runtime/logs" }

$activateScript = Join-Path $repoRoot ".venv/Scripts/Activate.ps1"
if (-Not (Test-Path $activateScript)) {
    Write-Error "Virtual environment not found. Run scripts/setup_windows.ps1 first."
    exit 1
}

. $activateScript

Set-Location $repoRoot
& python -m pytest
