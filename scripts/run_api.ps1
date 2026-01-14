param(
    [switch]$Reload
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$env:DOTENV_PATH = Join-Path $repoRoot "runtime/.env"
. "$PSScriptRoot/_load_env.ps1"

if (-not $env:APP_HOST) { $env:APP_HOST = "127.0.0.1" }
if (-not $env:APP_PORT) { $env:APP_PORT = "8080" }
if (-not $env:DATA_DIR) { $env:DATA_DIR = Join-Path $repoRoot "runtime/data" }
if (-not $env:LOG_DIR) { $env:LOG_DIR = Join-Path $repoRoot "runtime/logs" }

$activateScript = Join-Path $repoRoot ".venv/Scripts/Activate.ps1"
if (-Not (Test-Path $activateScript)) {
    Write-Error "Virtual environment not found. Run scripts/setup_windows.ps1 first."
    exit 1
}

. $activateScript
Set-Location $repoRoot

$uvicornArgs = @("thelighttrading.api.server:app", "--host", $env:APP_HOST, "--port", $env:APP_PORT)
if ($Reload) {
    $uvicornArgs += "--reload"
}

& python -m uvicorn @uvicornArgs
