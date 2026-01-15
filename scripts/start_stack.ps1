param()

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$RuntimeDir = Join-Path $RepoRoot "runtime"
$EnvFile = if ($env:DOTENV_PATH) { $env:DOTENV_PATH } else { Join-Path $RuntimeDir ".env" }
$LogDir = Join-Path $RuntimeDir "logs"
$LogFileOut = Join-Path $LogDir "uvicorn.out.log"
$LogFileErr = Join-Path $LogDir "uvicorn.err.log"
$startedLlm = $false
$startedApi = $false

if (-not $env:DOTENV_PATH) {
    $env:DOTENV_PATH = $EnvFile
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

$llmMode = $env:LLM_MODE
if ($llmMode -and $llmMode.ToLowerInvariant() -eq "local") {
    if (Test-LlmReady -Uris $llmUris) {
        Write-Output "LLM already running at $($llmUris -join ', ')."
    } else {
        & (Join-Path $PSScriptRoot "start_llm_bg.ps1")
        if ($LASTEXITCODE -ne 0) {
            exit 1
        }
        $startedLlm = $true
        if (-not (Wait-LlmReady -Uris $llmUris)) {
            Write-Error "LLM failed to become ready at $($llmUris -join ', ') within 30 seconds."
            & (Join-Path $PSScriptRoot "stop_llm.ps1") | Out-Null
            exit 1
        }
    }
} else {
    Write-Output "LLM_MODE is not local; skipping LLM startup."
}

& (Join-Path $PSScriptRoot "start_api_bg.ps1")
if ($LASTEXITCODE -ne 0) {
    Write-Output "=== Last 120 lines of $LogFileErr ==="
    if (Test-Path $LogFileErr) {
        Get-Content -Path $LogFileErr -Tail 120
    } else {
        Write-Output "(missing log file)"
    }
    Write-Output "=== Last 120 lines of $LogFileOut ==="
    if (Test-Path $LogFileOut) {
        Get-Content -Path $LogFileOut -Tail 120
    } else {
        Write-Output "(missing log file)"
    }
    if ($startedLlm) {
        & (Join-Path $PSScriptRoot "stop_llm.ps1") | Out-Null
    }
    exit 1
}
$startedApi = $true

& $healthScript -CheckLlm
if ($LASTEXITCODE -ne 0) {
    if ($startedApi) {
        & (Join-Path $PSScriptRoot "stop_api.ps1") | Out-Null
    }
    if ($startedLlm) {
        & (Join-Path $PSScriptRoot "stop_llm.ps1") | Out-Null
    }
    exit 1
}

Write-Output "Stack started successfully."
exit 0
