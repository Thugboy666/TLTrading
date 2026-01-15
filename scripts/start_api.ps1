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
$venvPython = Join-Path $repoRoot ".venv/Scripts/python.exe"
$pythonExe = if (Test-Path -Path $venvPython) { $venvPython } else { "python" }

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

function Get-ListenerPid {
    param(
        [int]$Port
    )
    $pids = @()
    $netTcpCommand = Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue
    if ($netTcpCommand) {
        try {
            $connections = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop
            $pids = $connections | Select-Object -ExpandProperty OwningProcess
        } catch {
            $pids = @()
        }
    }

    if (-not $pids -or $pids.Count -eq 0) {
        try {
            $netstatLines = netstat -ano | findstr ":$Port"
            foreach ($line in $netstatLines) {
                if ($line -match "LISTENING" -or $line -match "LISTEN") {
                    $parts = $line -split "\s+"
                    $pidValue = $parts[-1]
                    $parsedPid = 0
                    if ([int]::TryParse($pidValue, [ref]$parsedPid)) {
                        $pids += $parsedPid
                    }
                }
            }
        } catch {
            $pids = @()
        }
    }

    $uniquePids = $pids | Where-Object { $_ -ne $null } | Select-Object -Unique
    if ($uniquePids.Count -gt 1) {
        throw "Multiple listening PIDs found for port $Port: $($uniquePids -join ', ')."
    }
    if ($uniquePids.Count -eq 1) {
        return $uniquePids[0]
    }
    return $null
}

function Test-IsUvicornProcess {
    param(
        [int]$ProcessId
    )
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $process) {
        return $false
    }

    $commandLine = $null
    try {
        $commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId").CommandLine
    } catch {
        $commandLine = $null
    }

    if ($commandLine) {
        return ($commandLine -match "uvicorn") -or ($commandLine -match "thelighttrading.api.server")
    }

    return $process.ProcessName -match "python|uvicorn"
}

foreach ($dir in @($runtimeDir, (Join-Path $runtimeDir "data"), $logDir, $stateDir)) {
    if (-Not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

if (-not (Test-Path -Path $logFileOut)) { New-Item -ItemType File -Path $logFileOut -Force | Out-Null }
if (-not (Test-Path -Path $logFileErr)) { New-Item -ItemType File -Path $logFileErr -Force | Out-Null }

. "$PSScriptRoot/_load_env.ps1"

if (-not $env:APP_HOST) { $env:APP_HOST = "127.0.0.1" }
if (-not $env:APP_PORT) { $env:APP_PORT = "8080" }
if (-not $env:DATA_DIR) { $env:DATA_DIR = Join-Path $runtimeDir "data" }
if (-not $env:LOG_DIR) { $env:LOG_DIR = Join-Path $runtimeDir "logs" }

try {
    $existingListenerPid = Get-ListenerPid -Port ([int]$env:APP_PORT)
} catch {
    Write-Error $_
    $global:LASTEXITCODE = 1
    return
}

if ($existingListenerPid) {
    if (Test-IsUvicornProcess -ProcessId $existingListenerPid) {
        Write-Error "API already running with listener PID $existingListenerPid on port $($env:APP_PORT)."
    } else {
        Write-Error "Port $($env:APP_PORT) is already in use by PID $existingListenerPid."
    }
    $global:LASTEXITCODE = 1
    return
}

if (Test-Path $pidFile) {
    Remove-Item $pidFile -ErrorAction SilentlyContinue
}

Set-Location $repoRoot

$uvicornArgs = @("-m", "uvicorn", "thelighttrading.api.server:app", "--host", $env:APP_HOST, "--port", $env:APP_PORT)
if ($Reload) { $uvicornArgs += "--reload" }

$uvicornProcess = Start-Process -FilePath $pythonExe -ArgumentList $uvicornArgs -WorkingDirectory $repoRoot -PassThru -NoNewWindow -RedirectStandardOutput $logFileOut -RedirectStandardError $logFileErr

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

try {
    $listenerPid = Get-ListenerPid -Port ([int]$env:APP_PORT)
} catch {
    Write-Error $_
    Stop-Process -Id $uvicornProcess.Id -Force -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 1
    return
}

if (-not $listenerPid) {
    Write-Error "API became reachable, but no listener PID found for port $($env:APP_PORT)."
    Stop-Process -Id $uvicornProcess.Id -Force -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 1
    return
}

if (-not (Test-IsUvicornProcess -ProcessId $listenerPid)) {
    Write-Error "API health responded, but port $($env:APP_PORT) is owned by PID $listenerPid which does not appear to be uvicorn."
    Stop-Process -Id $uvicornProcess.Id -Force -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 1
    return
}

Set-Content -Path $pidFile -Value $listenerPid
$status = [ordered]@{
    pid        = $listenerPid
    started_at = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    port       = [int]$env:APP_PORT
    status     = "running"
}
$status | ConvertTo-Json | Set-Content -Path $statusFile
Write-Output "API started with uvicorn PID $listenerPid."
$global:LASTEXITCODE = 0
return
