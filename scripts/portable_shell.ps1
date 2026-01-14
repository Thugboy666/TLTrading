$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($repoRoot)) {
    Write-Error "Unable to determine repository root."
    exit 1
}

$resolvedRepoRoot = Resolve-Path -LiteralPath $repoRoot -ErrorAction SilentlyContinue
if (-not $resolvedRepoRoot) {
    Write-Error "Unable to resolve repository root at '$repoRoot'."
    exit 1
}

$repoRoot = $resolvedRepoRoot.Path
$dotenvPath = Join-Path $repoRoot "runtime\.env"
$logsDir = Join-Path $repoRoot "runtime\logs"
$activateScript = Join-Path $repoRoot ".venv\Scripts\Activate.ps1"

$childScript = @"
Set-Location -LiteralPath '$repoRoot'

if (Test-Path '$dotenvPath') {
    `$env:DOTENV_PATH = '$dotenvPath'
} else {
    Remove-Item Env:DOTENV_PATH -ErrorAction SilentlyContinue
}

Remove-Item Env:PACKET_SIGNING_PRIVATE_KEY_BASE64 -ErrorAction SilentlyContinue
Remove-Item Env:PACKET_SIGNING_PUBLIC_KEY_BASE64 -ErrorAction SilentlyContinue

if (-Not (Test-Path '$logsDir')) {
    New-Item -ItemType Directory -Force -Path '$logsDir' | Out-Null
}

if (Test-Path '$activateScript') {
    . '$activateScript'
} else {
    Write-Host "[portable] .venv not found. Run scripts\\bootstrap_portable.ps1 first."
}

`$pythonExe = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not `$pythonExe) {
    `$pythonExe = "python not found"
}
Write-Host "[portable] OK repo: $repoRoot python: `$pythonExe"
"@

Start-Process "powershell" -WorkingDirectory $repoRoot -ArgumentList @(
    "-NoExit",
    "-Command",
    $childScript
)
