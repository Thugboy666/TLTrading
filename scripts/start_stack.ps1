param()

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeDir = Join-Path $repoRoot "runtime"
$envFile = Join-Path $runtimeDir ".env"

if (Test-Path -Path $envFile) {
    $env:DOTENV_PATH = $envFile
} else {
    Remove-Item Env:DOTENV_PATH -ErrorAction SilentlyContinue
}

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
}

& (Join-Path $PSScriptRoot "start_api_bg.ps1")
if ($LASTEXITCODE -ne 0) {
    exit 1
}

& $healthScript -CheckLlm
if ($LASTEXITCODE -ne 0) {
    exit 1
}

Write-Output "Stack started successfully."
exit 0
