$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeDir = Join-Path $repoRoot "runtime"
$pidFile = Join-Path $runtimeDir "api.pid"
$logFile = Join-Path $repoRoot "logs/uvicorn.log"
$startScript = Join-Path $PSScriptRoot "start_api.ps1"

if (-Not (Test-Path $runtimeDir)) {
    New-Item -ItemType Directory -Path $runtimeDir | Out-Null
}

if (Test-Path $pidFile) {
    try {
        $existingPid = Get-Content $pidFile -ErrorAction Stop
        if ($existingPid) {
            $proc = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
            if ($proc) {
                Write-Warning "API already appears to be running with PID $existingPid. Use scripts/stop_api.ps1 to stop it."
                exit 1
            }
        }
    } catch {
        Write-Warning "Could not read existing PID file. It will be overwritten."
    }
}

$logDir = Split-Path $logFile -Parent
if (-Not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

$process = Start-Process -FilePath "powershell" -ArgumentList @("-NoLogo", "-NoProfile", "-File", "`"$startScript`"") -WorkingDirectory $repoRoot -RedirectStandardOutput $logFile -RedirectStandardError $logFile -PassThru

if (-not $process) {
    Write-Error "Failed to start API in background."
    exit 1
}

Set-Content -Path $pidFile -Value $process.Id
Write-Output "API started in background with PID $($process.Id). Logs: $logFile"
