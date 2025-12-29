$repoRoot = Split-Path -Parent $PSScriptRoot
$env:DOTENV_PATH = Join-Path $repoRoot "runtime/.env"

Remove-Item Env:PACKET_SIGNING_PRIVATE_KEY_BASE64 -ErrorAction SilentlyContinue
Remove-Item Env:PACKET_SIGNING_PUBLIC_KEY_BASE64 -ErrorAction SilentlyContinue

$runtimeDir = Join-Path $repoRoot "runtime"
$dataDir = Join-Path $repoRoot "data"
$logsDir = Join-Path $repoRoot "logs"
$runtimeDataDir = Join-Path $runtimeDir "data"
$runtimeLogsDir = Join-Path $runtimeDir "logs"

foreach ($dir in @($runtimeDir, $dataDir, $logsDir, $runtimeDataDir, $runtimeLogsDir)) {
    if (-Not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

$runApiScript = Join-Path $PSScriptRoot "run_api.ps1"
& $runApiScript @args
