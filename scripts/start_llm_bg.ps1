param(
    [string]$ModelPath,
    [Alias('Host')][string]$llmHost = "127.0.0.1",
    [Alias('Port')][int]$llmPort = 8081
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeDir = Join-Path $repoRoot "runtime"
$binDir = Join-Path $runtimeDir "bin/llama"
$logDir = Join-Path $runtimeDir "logs"
$chatModelDir = Join-Path $runtimeDir "models/chat"
$embedModelDir = Join-Path $runtimeDir "models/embed"
$stateDir = Join-Path $runtimeDir "state"
$pidFile = Join-Path $runtimeDir "llama.pid"
$logFileOut = Join-Path $logDir "llama.out.log"
$logFileErr = Join-Path $logDir "llama.err.log"
$envFile = Join-Path $runtimeDir ".env"


$envFileExists = Test-Path -Path $envFile
if ($envFileExists) {
    $env:DOTENV_PATH = $envFile
} else {
    Remove-Item Env:DOTENV_PATH -ErrorAction SilentlyContinue
}

Remove-Item Env:PACKET_SIGNING_PRIVATE_KEY_BASE64 -ErrorAction SilentlyContinue
Remove-Item Env:PACKET_SIGNING_PUBLIC_KEY_BASE64  -ErrorAction SilentlyContinue

foreach ($dir in @($runtimeDir, $binDir, $logDir, $chatModelDir, $embedModelDir, $stateDir)) {
    if (-not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

if (-not (Test-Path -Path $logFileOut)) { New-Item -ItemType File -Path $logFileOut | Out-Null }
if (-not (Test-Path -Path $logFileErr)) { New-Item -ItemType File -Path $logFileErr | Out-Null }

if (Test-Path $pidFile) {
    $existingPidContent = Get-Content -Path $pidFile -Raw -ErrorAction SilentlyContinue
    $existingPidValue = $existingPidContent.Trim()
    $existingPid = 0
    if ([int]::TryParse($existingPidValue, [ref]$existingPid)) {
        $existingProcess = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
        if ($existingProcess) {
            Write-Warning "LLM server already appears to be running with PID $existingPid. Use scripts/stop_llm.ps1 to stop it."
            $global:LASTEXITCODE = 1
            return
        }
    }

    Remove-Item $pidFile -ErrorAction SilentlyContinue
}

. "$PSScriptRoot/_load_env.ps1"

if (-not $PSBoundParameters.ContainsKey('llmHost') -and $env:LLM_HOST) {
    $llmHost = $env:LLM_HOST
}
if (-not $PSBoundParameters.ContainsKey('llmPort') -and $env:LLM_PORT) {
    $parsedPort = 0
    if ([int]::TryParse($env:LLM_PORT, [ref]$parsedPort) -and $parsedPort -gt 0) {
        $llmPort = $parsedPort
    }
}
if (-not $PSBoundParameters.ContainsKey('llmHost') -and $env:LOCAL_LLM_SERVER_URL) {
    try {
        $uri = [System.Uri]$env:LOCAL_LLM_SERVER_URL
        if ($uri.Host) { $llmHost = $uri.Host }
        if ($uri.Port -gt 0) { $llmPort = $uri.Port }
    } catch {
        # ignore malformed URI
    }
} elseif (-not $PSBoundParameters.ContainsKey('llmHost') -and $env:LLM_BASE_URL) {
    try {
        $uri = [System.Uri]$env:LLM_BASE_URL
        if ($uri.Host) { $llmHost = $uri.Host }
        if ($uri.Port -gt 0) { $llmPort = $uri.Port }
    } catch {
        # ignore malformed URI
    }
}

$llmExe = $null
$llmCandidates = @("rpc-server.exe", "server.exe")
foreach ($exeName in $llmCandidates) {
    $candidatePath = Join-Path $binDir $exeName
    if (Test-Path -Path $candidatePath) {
        $llmExe = $candidatePath
        break
    }
}

if (-not $llmExe) {
    $wildcardCandidate = Get-ChildItem -Path $binDir -Filter "*server*.exe" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($wildcardCandidate) {
        $llmExe = $wildcardCandidate.FullName
    }
}

if (-not $llmExe) {
    $expectedList = $llmCandidates -join ", "
    Write-Error "llama.cpp server binary not found under $binDir. Expected one of: $expectedList or any *server*.exe. Copy the llama.cpp release folder into runtime/bin/llama/."
    $global:LASTEXITCODE = 1
    return
}

$llmExeName = [System.IO.Path]::GetFileName($llmExe)
$isRpcServer = $llmExeName -ieq "rpc-server.exe"
$supportsLogDisable = $false
try {
    $helpText = & $llmExe "--help" 2>&1 | Out-String
    if ($helpText -match "--log-disable") {
        $supportsLogDisable = $true
    }
} catch {
    $supportsLogDisable = $false
}

if (-not $isRpcServer) {
    if (-not $ModelPath) {
        $modelCandidates = @()
        if ($env:LLM_CHAT_MODEL) { $modelCandidates += $env:LLM_CHAT_MODEL }
        if ($env:LOCAL_CHAT_MODEL_DEFAULT) { $modelCandidates += $env:LOCAL_CHAT_MODEL_DEFAULT }
        if ($env:LOCAL_CHAT_MODEL_QWEN) { $modelCandidates += $env:LOCAL_CHAT_MODEL_QWEN }
        if ($env:LOCAL_CHAT_MODEL_MISTRAL) { $modelCandidates += $env:LOCAL_CHAT_MODEL_MISTRAL }
        if ($env:LLAMA_CHAT_MODEL) { $modelCandidates += $env:LLAMA_CHAT_MODEL }
        foreach ($candidate in $modelCandidates) {
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -Path $candidate)) {
                $ModelPath = $candidate
                break
            }
        }
    }

    if (-not $ModelPath) {
        $firstGguf = Get-ChildItem -Path $chatModelDir -Filter "*.gguf" -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($firstGguf) {
            $ModelPath = $firstGguf.FullName
        }
    }

    if (-not $ModelPath) {
        Write-Error "No chat model configured. Set LLM_CHAT_MODEL in runtime/.env or place a GGUF file under runtime/models/chat/."
        $global:LASTEXITCODE = 1
        return
    }

    if (-not (Test-Path -Path $ModelPath)) {
        Write-Error "Model file not found at $ModelPath. Place a GGUF chat model under runtime/models/chat/."
        $global:LASTEXITCODE = 1
        return
    }
}

$threadCount = 0
if ($env:LLM_THREADS) {
    [int]::TryParse($env:LLM_THREADS, [ref]$threadCount) | Out-Null
}

if ($isRpcServer) {
    $arguments = @("-H", $llmHost, "-p", $llmPort)
    if ($threadCount -gt 0) {
        $arguments += @("-t", $threadCount)
    }
} else {
    $arguments = @("--host", $llmHost, "--port", $llmPort)
    if ($supportsLogDisable) {
        $arguments += "--log-disable"
    }
    $arguments += @("-m", $ModelPath, "--embedding")
}

$llamaProcess = Start-Process -FilePath $llmExe -ArgumentList $arguments -WorkingDirectory $binDir -PassThru -NoNewWindow -RedirectStandardOutput $logFileOut -RedirectStandardError $logFileErr

if (-not $llamaProcess) {
    Write-Error "Failed to start llama.cpp server."
    $global:LASTEXITCODE = 1
    return
}

$llmPid = $llamaProcess.Id
Set-Content -Path $pidFile -Value $llmPid

function Test-TcpPort {
    param(
        [string]$HostName,
        [int]$PortNumber,
        [int]$TimeoutMs = 500
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $asyncResult = $client.BeginConnect($HostName, $PortNumber, $null, $null)
        if (-not $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return $false
        }
        $client.EndConnect($asyncResult) | Out-Null
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Test-LlmReady {
    param(
        [System.Diagnostics.Process]$Process,
        [string[]]$Uris
    )
    if (-not $Process -or $Process.HasExited) {
        return $false
    }
    if (Test-TcpPort -HostName $llmHost -PortNumber $llmPort) {
        return $true
    }
    foreach ($uri in $Uris) {
        try {
            $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
                return $true
            }
        } catch {
            # keep trying other endpoints
        }
    }
    return $false
}

$healthUris = @(
    "http://$llmHost`:$llmPort/health",
    "http://$llmHost`:$llmPort/v1/models"
)
$ready = $false
for ($attempt = 0; $attempt -lt 40; $attempt++) {
    if ($llamaProcess.HasExited) {
        break
    }
    if (Test-LlmReady -Process $llamaProcess -Uris $healthUris) {
        $ready = $true
        break
    }
    Start-Sleep -Milliseconds 500
}

if (-not $ready) {
    Write-Error "LLM server failed to become reachable at $($healthUris -join ', ') within 20 seconds."
    Stop-Process -Id $llamaProcess.Id -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $pidFile -ErrorAction SilentlyContinue
    Write-Output "=== Last 60 lines of $logFileErr ==="
    if (Test-Path $logFileErr) {
        Get-Content -Path $logFileErr -Tail 60
    } else {
        Write-Output "(missing log file)"
    }
    Write-Output "=== Last 60 lines of $logFileOut ==="
    if (Test-Path $logFileOut) {
        Get-Content -Path $logFileOut -Tail 60
    } else {
        Write-Output "(missing log file)"
    }
    $global:LASTEXITCODE = 1
    return
}
Write-Output "LLM server ready with PID $llmPid (host $llmHost port $llmPort). Logs: stdout -> $logFileOut, stderr -> $logFileErr"
$global:LASTEXITCODE = 0
return
