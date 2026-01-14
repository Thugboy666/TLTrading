$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeRoot = Join-Path $repoRoot "runtime"
$logsDir = Join-Path $runtimeRoot "logs"
$dotenvPath = Join-Path $runtimeRoot ".env"
$activateScript = Join-Path $repoRoot ".venv/Scripts/Activate.ps1"

$childScript = @'
param(
    [string]$RepoRoot,
    [string]$RuntimeRoot,
    [string]$LogsDir,
    [string]$DotenvPath,
    [string]$ActivateScript
)

Set-Location -LiteralPath $RepoRoot

if (Test-Path $DotenvPath) {
    $env:DOTENV_PATH = $DotenvPath
} else {
    Remove-Item Env:DOTENV_PATH -ErrorAction SilentlyContinue
}

Remove-Item Env:PACKET_SIGNING_PRIVATE_KEY_BASE64 -ErrorAction SilentlyContinue
Remove-Item Env:PACKET_SIGNING_PUBLIC_KEY_BASE64 -ErrorAction SilentlyContinue

if (-Not (Test-Path $LogsDir)) {
    New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null
}

if (Test-Path $ActivateScript) {
    . $ActivateScript
} else {
    Write-Host "[portable] .venv not found. Run scripts\\bootstrap_portable.ps1 first."
}
'@

Start-Process "powershell" -WorkingDirectory $repoRoot -ArgumentList @(
    "-NoExit",
    "-Command",
    $childScript,
    $repoRoot,
    $runtimeRoot,
    $logsDir,
    $dotenvPath,
    $activateScript
)
