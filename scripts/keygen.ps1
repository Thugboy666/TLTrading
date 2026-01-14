$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeDir = Join-Path $repoRoot "runtime"
$envFile = Join-Path $runtimeDir ".env"

if (-Not (Test-Path $runtimeDir)) {
    New-Item -ItemType Directory -Path $runtimeDir | Out-Null
}

$activateScript = Join-Path $repoRoot ".venv/Scripts/Activate.ps1"
if (-Not (Test-Path $activateScript)) {
    Write-Error "Virtual environment not found. Run scripts/setup_windows.ps1 first."
    exit 1
}

. $activateScript
Set-Location $repoRoot

$env:DOTENV_PATH = $envFile

Write-Host "Generating packet signing keypair..."
& python -m thelighttrading.tools.keygen --out $envFile --overwrite
Write-Host "Signing keys written to $envFile (private key not displayed)."
