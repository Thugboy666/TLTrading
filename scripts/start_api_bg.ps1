$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeDir = Join-Path $repoRoot "runtime"
$logDir = Join-Path $runtimeDir "logs"
$logFileOut = Join-Path $logDir "uvicorn.out.log"
$logFileErr = Join-Path $logDir "uvicorn.err.log"
$startScript = Join-Path $PSScriptRoot "start_api.ps1"
$envFile = Join-Path $runtimeDir ".env"
$pidFile = Join-Path $runtimeDir "api.pid"

if (Test-Path -Path $envFile) {
    $env:DOTENV_PATH = $envFile
} else {
    Remove-Item Env:DOTENV_PATH -ErrorAction SilentlyContinue
}

. "$PSScriptRoot/_load_env.ps1"

if (-not $env:APP_HOST) { $env:APP_HOST = "127.0.0.1" }
if (-not $env:APP_PORT) { $env:APP_PORT = "8080" }

foreach ($dir in @($runtimeDir, $logDir)) {
    if (-Not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

if (-not (Test-Path $logFileOut)) { New-Item -ItemType File -Path $logFileOut -Force | Out-Null }
if (-not (Test-Path $logFileErr)) { New-Item -ItemType File -Path $logFileErr -Force | Out-Null }

$arguments = @(
    "-NoLogo",
    "-NoProfile",
    "-File",
    "`"$startScript`"",
    "1>>",
    "`"$logFileOut`"",
    "2>>",
    "`"$logFileErr`""
)

$process = Start-Process -FilePath "powershell" -ArgumentList $arguments -WorkingDirectory $repoRoot -PassThru

if (-not $process) {
    Write-Error "Failed to start API in background."
    $global:LASTEXITCODE = 1
    return
}

Write-Output "API start script launched in background with wrapper PID $($process.Id). Logs: stdout -> $logFileOut, stderr -> $logFileErr"
$healthUri = "http://$($env:APP_HOST):$($env:APP_PORT)/health"
$ready = $false
for ($attempt = 0; $attempt -lt 60; $attempt++) {
    try {
        $response = Invoke-WebRequest -Uri $healthUri -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        $health = $response.Content | ConvertFrom-Json
        if ($health.ok) {
            $ready = $true
            break
        }
    } catch {
        Start-Sleep -Milliseconds 500
    }
}

if (-not $ready) {
    Write-Error "API failed to become ready at $healthUri within 30 seconds."
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
    if (Test-Path $pidFile) {
        $pidValue = (Get-Content -Path $pidFile -Raw -ErrorAction SilentlyContinue).Trim()
        $parsedPid = 0
        if ([int]::TryParse($pidValue, [ref]$parsedPid)) {
            Stop-Process -Id $parsedPid -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -Path $pidFile -ErrorAction SilentlyContinue
    }
    $global:LASTEXITCODE = 1
    return
}

$apiPid = $null
if (Test-Path $pidFile) {
    $pidValue = (Get-Content -Path $pidFile -Raw -ErrorAction SilentlyContinue).Trim()
    $parsedPid = 0
    if ([int]::TryParse($pidValue, [ref]$parsedPid)) {
        $apiPid = $parsedPid
    }
}

if ($apiPid) {
    Write-Output "API ready at $healthUri with uvicorn PID $apiPid."
} else {
    Write-Output "API ready at $healthUri."
}
$global:LASTEXITCODE = 0
return
