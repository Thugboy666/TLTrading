param()

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeDir = Join-Path $repoRoot "runtime"
$envFile = Join-Path $runtimeDir ".env"
$logDir = Join-Path $runtimeDir "logs"
$logFileOut = Join-Path $logDir "uvicorn.out.log"
$logFileErr = Join-Path $logDir "uvicorn.err.log"

if (Test-Path -Path $envFile) {
    $env:DOTENV_PATH = $envFile
} else {
    Remove-Item Env:DOTENV_PATH -ErrorAction SilentlyContinue
}

Remove-Item Env:PACKET_SIGNING_PRIVATE_KEY_BASE64 -ErrorAction SilentlyContinue
Remove-Item Env:PACKET_SIGNING_PUBLIC_KEY_BASE64  -ErrorAction SilentlyContinue

. "$PSScriptRoot/_load_env.ps1"

if (-not $env:APP_HOST) { $env:APP_HOST = "127.0.0.1" }
if (-not $env:APP_PORT) { $env:APP_PORT = "8080" }
if (-not $env:LLM_HOST) { $env:LLM_HOST = "127.0.0.1" }
if (-not $env:LLM_PORT) { $env:LLM_PORT = "8081" }

$healthScript = Join-Path $PSScriptRoot "health_check.ps1"
& $healthScript -CheckLlm
if ($LASTEXITCODE -eq 0) {
    Write-Output "Stack already running. API http://$($env:APP_HOST):$($env:APP_PORT) LLM http://$($env:LLM_HOST):$($env:LLM_PORT)"
    exit 0
}

function Test-LlmReady {
    param(
        [string[]]$Uris
    )
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

function Wait-LlmReady {
    param(
        [string[]]$Uris,
        [int]$Attempts = 60
    )
    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        if (Test-LlmReady -Uris $Uris) {
            return $true
        }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

$llmUris = @(
    "http://$($env:LLM_HOST):$($env:LLM_PORT)/health",
    "http://$($env:LLM_HOST):$($env:LLM_PORT)/v1/models"
)

if (Test-LlmReady -Uris $llmUris) {
    Write-Output "LLM already running at $($llmUris -join ', ')."
} else {
    & (Join-Path $PSScriptRoot "start_llm_bg.ps1")
    if ($LASTEXITCODE -ne 0) {
        exit 1
    }
    if (-not (Wait-LlmReady -Uris $llmUris)) {
        Write-Error "LLM failed to become ready at $($llmUris -join ', ') within 30 seconds."
        exit 1
    }
}

& (Join-Path $PSScriptRoot "start_api_bg.ps1")
if ($LASTEXITCODE -ne 0) {
    Write-Output "=== Last 120 lines of $logFileErr ==="
    if (Test-Path $logFileErr) {
        Get-Content -Path $logFileErr -Tail 120
    } else {
        Write-Output "(missing log file)"
    }
    Write-Output "=== Last 120 lines of $logFileOut ==="
    if (Test-Path $logFileOut) {
        Get-Content -Path $logFileOut -Tail 120
    } else {
        Write-Output "(missing log file)"
    }
    exit 1
}

& $healthScript -CheckLlm
if ($LASTEXITCODE -ne 0) {
    exit 1
}

Write-Output "Stack started successfully."
exit 0
