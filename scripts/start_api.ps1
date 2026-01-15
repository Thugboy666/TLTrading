param(
    [switch]$Reload
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeDir = Join-Path $repoRoot "runtime"
$stateDir = Join-Path $runtimeDir "state"
$pidFile = Join-Path $runtimeDir "api.pid"
$statusFile = Join-Path $stateDir "api.status.json"
$logDir = Join-Path $runtimeDir "logs"
$logFileOut = Join-Path $logDir "uvicorn.out.log"
$logFileErr = Join-Path $logDir "uvicorn.err.log"
$envFile = Join-Path $runtimeDir ".env"
$envExample = Join-Path $runtimeDir ".env.example"
$envFileExists = Test-Path -Path $envFile

if ($envFileExists) {
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
            "LLM_BACKEND=llamacpp",
            "LLM_HOST=127.0.0.1",
            "LLM_PORT=8081",
            "LLM_CHAT_MODEL=",
            "LLM_EMBED_MODEL=",
            "LOCAL_LLM_SERVER_URL=http://127.0.0.1:8081",
            "LOCAL_CHAT_MODEL_DEFAULT=./runtime/models/chat/chat.gguf",
            "LOCAL_CHAT_MODEL_QWEN=",
            "LOCAL_CHAT_MODEL_MISTRAL=",
            "LOCAL_EMBED_MODEL=./runtime/models/embed/embed.gguf",
            "# PACKET_SIGNING_PRIVATE_KEY_BASE64=",
            "# PACKET_SIGNING_PUBLIC_KEY_BASE64="
        ) | Set-Content -Path $envExample
    }
    Write-Output "runtime/.env not found. Copy runtime/.env.example to runtime/.env and adjust values."
}

Remove-Item Env:PACKET_SIGNING_PRIVATE_KEY_BASE64 -ErrorAction SilentlyContinue
Remove-Item Env:PACKET_SIGNING_PUBLIC_KEY_BASE64  -ErrorAction SilentlyContinue

foreach ($dir in @($runtimeDir, (Join-Path $runtimeDir "data"), $logDir, $stateDir)) {
    if (-Not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

if (-not (Test-Path -Path $logFileOut)) { New-Item -ItemType File -Path $logFileOut -Force | Out-Null }
if (-not (Test-Path -Path $logFileErr)) { New-Item -ItemType File -Path $logFileErr -Force | Out-Null }

if (Test-Path $pidFile) {
    $existingPidContent = Get-Content -Path $pidFile -Raw -ErrorAction SilentlyContinue
    $existingPidValue = $existingPidContent.Trim()
    $existingPid = 0
    if ([int]::TryParse($existingPidValue, [ref]$existingPid)) {
        $existingProcess = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
        if ($existingProcess) {
            Write-Warning "API already appears to be running with PID $existingPid. Use scripts/stop_api.ps1 to stop it."
            $global:LASTEXITCODE = 1
            return
        }
    }

    Remove-Item $pidFile -ErrorAction SilentlyContinue
}

if ($envFileExists) {
    $env:DOTENV_PATH = $envFile
} else {
    Remove-Item Env:DOTENV_PATH -ErrorAction SilentlyContinue
}
. "$PSScriptRoot/_load_env.ps1"

if (-not $env:APP_HOST) { $env:APP_HOST = "127.0.0.1" }
if (-not $env:APP_PORT) { $env:APP_PORT = "8080" }
if (-not $env:DATA_DIR) { $env:DATA_DIR = Join-Path $runtimeDir "data" }
if (-not $env:LOG_DIR) { $env:LOG_DIR = Join-Path $runtimeDir "logs" }

$activateScript = Join-Path $repoRoot ".venv/Scripts/Activate.ps1"
if (-Not (Test-Path $activateScript)) {
    Write-Error "Virtual environment not found. Run scripts/setup_windows.ps1 first."
    $global:LASTEXITCODE = 1
    return
}

. $activateScript
Set-Location $repoRoot

$uvicornArgs = @("-m", "uvicorn", "thelighttrading.api.server:app", "--host", $env:APP_HOST, "--port", $env:APP_PORT)
if ($Reload) { $uvicornArgs += "--reload" }

$uvicornProcess = Start-Process -FilePath "python" -ArgumentList $uvicornArgs -WorkingDirectory $repoRoot -PassThru -NoNewWindow -RedirectStandardOutput $logFileOut -RedirectStandardError $logFileErr

if (-not $uvicornProcess) {
    Write-Error "Failed to start uvicorn process."
    $global:LASTEXITCODE = 1
    return
}

$healthUri = "http://$($env:APP_HOST):$($env:APP_PORT)/health"
$ready = $false
for ($attempt = 0; $attempt -lt 20; $attempt++) {
    try {
        $null = Invoke-WebRequest -Uri $healthUri -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        $ready = $true
        break
    } catch {
        Start-Sleep -Seconds 1
    }
}

if (-not $ready) {
    Write-Error "API failed to become reachable at $healthUri within 20 seconds."
    Stop-Process -Id $uvicornProcess.Id -Force -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 1
    return
}

Set-Content -Path $pidFile -Value $uvicornProcess.Id
$status = [ordered]@{
    pid        = $uvicornProcess.Id
    started_at = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    port       = [int]$env:APP_PORT
    status     = "running"
}
$status | ConvertTo-Json | Set-Content -Path $statusFile
Write-Output "API started with uvicorn PID $($uvicornProcess.Id)."
$global:LASTEXITCODE = 0
return
