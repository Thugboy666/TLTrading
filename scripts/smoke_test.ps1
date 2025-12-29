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
