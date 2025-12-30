param(
    [switch]$CheckLlm
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$pidFile = Join-Path $repoRoot "runtime/api.pid"
$envFile = Join-Path $repoRoot "runtime/.env"

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

$uri = "http://$($env:APP_HOST):$($env:APP_PORT)/health"

$expectedPid = $null
$pidFileMissing = $true
if (Test-Path -Path $pidFile) {
    $pidFileMissing = $false
    try {
        $pidContent = Get-Content -Path $pidFile -Raw -ErrorAction Stop
        $pidValue = $pidContent.Trim()
        $parsedPid = 0
        if ([int]::TryParse($pidValue, [ref]$parsedPid)) {
            $expectedPid = $parsedPid
        }
    } catch {
        $pidFileMissing = $true
    }
}

try {
    $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -ErrorAction Stop
} catch {
    Write-Output "DOWN: unable to reach $uri ($_ )"
    exit 1
}

try {
    $health = $response.Content | ConvertFrom-Json
} catch {
    Write-Output "DOWN: invalid JSON response from $uri"
    exit 1
}

if (-not $health) {
    Write-Output "DOWN: empty health response"
    exit 1
}

if (-not $health.ok) {
    Write-Output "DEGRADED: health reported ok=false"
    exit 1
}

if ($pidFileMissing) {
    Write-Output "DEGRADED: PID file missing while health reports ok"
    exit 1
}

if ($expectedPid -and $health.pid -ne $expectedPid) {
    Write-Output "DEGRADED: PID mismatch (expected $expectedPid, got $($health.pid))"
    exit 1
}

Write-Output "OK: pid $($health.pid) uptime $($health.uptime_seconds)s mode $($health.llm_mode)"
if ($CheckLlm) {
    $llmHealth = "http://$($env:APP_HOST):$($env:APP_PORT)/llm/health"
    try {
        $llmResponse = Invoke-WebRequest -Uri $llmHealth -UseBasicParsing -ErrorAction Stop
        $llmJson = $llmResponse.Content | ConvertFrom-Json
        if (-not $llmJson.ok) {
            Write-Output "LLM DOWN: $($llmJson.reason)"
            exit 1
        }
        Write-Output "LLM OK: $llmHealth status $($llmResponse.StatusCode) mode $($llmJson.mode) backend $($llmJson.backend)"
    } catch {
        Write-Output "LLM DOWN: unable to reach $llmHealth ($_ )"
        exit 1
    }
}
exit 0
