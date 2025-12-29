param(
    [string]$ModelPath,
    [string]$Host = "127.0.0.1",
    [int]$Port = 8081
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeDir = Join-Path $repoRoot "runtime"
$binDir = Join-Path $runtimeDir "bin/llama"
$logDir = Join-Path $runtimeDir "logs"
$chatModelDir = Join-Path $runtimeDir "models/chat"
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

foreach ($dir in @($runtimeDir, $binDir, $logDir, $chatModelDir, (Join-Path $runtimeDir "models/embed"))) {
    if (-not (Test-Path -Path $dir)) {
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
            Write-Warning "LLM server already appears to be running with PID $existingPid. Use scripts/stop_llm.ps1 to stop it."
            $global:LASTEXITCODE = 1
            return
        }
    }

    Remove-Item $pidFile -ErrorAction SilentlyContinue
}

. "$PSScriptRoot/_load_env.ps1"

if (-not $PSBoundParameters.ContainsKey('Host') -and $env:LLM_BASE_URL) {
    try {
        $uri = [System.Uri]$env:LLM_BASE_URL
        if ($uri.Host) { $Host = $uri.Host }
        if ($uri.Port -gt 0) { $Port = $uri.Port }
    } catch {
        # ignore malformed URI
    }
}

$serverExe = Join-Path $binDir "server.exe"
if (-not (Test-Path -Path $serverExe)) {
    Write-Error "llama.cpp server.exe not found at $serverExe. Download the llama.cpp release and place the server binary there."
    $global:LASTEXITCODE = 1
    return
}

if (-not $ModelPath -and $env:LLAMA_CHAT_MODEL) {
    $ModelPath = $env:LLAMA_CHAT_MODEL
}

if (-not $ModelPath) {
    $ModelPath = Join-Path $runtimeDir "models/chat/chat.gguf"
}

if (-not (Test-Path -Path $ModelPath)) {
    Write-Error "Model file not found at $ModelPath. Place a GGUF chat model under runtime/models/chat/."
    $global:LASTEXITCODE = 1
    return
}

$arguments = @("--host", $Host, "--port", $Port, "--log-disable", "-m", $ModelPath, "--embedding")

$llamaProcess = Start-Process -FilePath $serverExe -ArgumentList $arguments -WorkingDirectory $binDir -PassThru -NoNewWindow -RedirectStandardOutput $logFileOut -RedirectStandardError $logFileErr

if (-not $llamaProcess) {
    Write-Error "Failed to start llama.cpp server."
    $global:LASTEXITCODE = 1
    return
}

$llmPid = $llamaProcess.Id
Set-Content -Path $pidFile -Value $llmPid
Write-Output "LLM server started with PID $llmPid (host $Host port $Port). Logs: stdout -> $logFileOut, stderr -> $logFileErr"
$global:LASTEXITCODE = 0
return
