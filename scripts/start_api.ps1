$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeDir = Join-Path $repoRoot "runtime"
$envFile = Join-Path $runtimeDir ".env"
$envExample = Join-Path $runtimeDir ".env.example"

if (Test-Path -Path $envFile) {
    $env:DOTENV_PATH = $envFile
} else {
    Remove-Item Env:DOTENV_PATH -ErrorAction SilentlyContinue
    if (-not (Test-Path -Path $envExample)) {
        @(
            "APP_HOST=127.0.0.1",
            "APP_PORT=8080",
            "DATA_DIR=./data",
            "LOG_DIR=./logs",
            "LLM_MODE=mock",
            "LLM_BASE_URL=http://127.0.0.1:8081",
            "# PACKET_SIGNING_PRIVATE_KEY_BASE64=",
            "# PACKET_SIGNING_PUBLIC_KEY_BASE64="
        ) | Set-Content -Path $envExample
    }
    Write-Output "runtime/.env not found. Copy runtime/.env.example to runtime/.env and adjust values."
}

Remove-Item Env:PACKET_SIGNING_PRIVATE_KEY_BASE64 -ErrorAction SilentlyContinue
Remove-Item Env:PACKET_SIGNING_PUBLIC_KEY_BASE64  -ErrorAction SilentlyContinue

$runtimeDataDir = Join-Path $runtimeDir "data"
$runtimeLogsDir = Join-Path $runtimeDir "logs"

foreach ($dir in @($runtimeDir, $runtimeDataDir, $runtimeLogsDir)) {
    if (-Not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

$runApiScript = Join-Path $PSScriptRoot "run_api.ps1"
& $runApiScript @args
