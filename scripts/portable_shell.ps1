$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeRoot = Join-Path $repoRoot "runtime"
$logsDir = Join-Path $runtimeRoot "logs"

$dotenvPath = Join-Path $runtimeRoot ".env"
if (Test-Path $dotenvPath) {
    $env:DOTENV_PATH = $dotenvPath
}

Remove-Item Env:PACKET_SIGNING_PRIVATE_KEY_BASE64 -ErrorAction SilentlyContinue
Remove-Item Env:PACKET_SIGNING_PUBLIC_KEY_BASE64 -ErrorAction SilentlyContinue

if (-Not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
}

$activateScript = Join-Path $repoRoot ".venv/Scripts/Activate.ps1"
if (-Not (Test-Path $activateScript)) {
    Write-Host "[portable] .venv not found. Run scripts\\bootstrap_portable.ps1 first."
}

$commands = @(
    "Set-Location -LiteralPath \"$repoRoot\""
)

if (Test-Path $activateScript) {
    $commands += ". \"$activateScript\""
}

$command = $commands -join "; "

powershell -NoExit -Command $command
