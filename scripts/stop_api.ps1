$repoRoot = Split-Path -Parent $PSScriptRoot
$pidFile = Join-Path $repoRoot "runtime/api.pid"

if (-Not (Test-Path $pidFile)) {
    Write-Warning "PID file not found at $pidFile. Nothing to stop."
    exit 0
}

try {
    $pid = Get-Content $pidFile -ErrorAction Stop
} catch {
    Write-Warning "Could not read PID file."
    exit 1
}

if (-not $pid) {
    Write-Warning "PID file is empty."
    Remove-Item $pidFile -ErrorAction SilentlyContinue
    exit 1
}

$process = Get-Process -Id $pid -ErrorAction SilentlyContinue
if (-not $process) {
    Write-Warning "No process found with PID $pid. Cleaning up PID file."
    Remove-Item $pidFile -ErrorAction SilentlyContinue
    exit 0
}

try {
    Stop-Process -Id $pid -Force -ErrorAction Stop
    Write-Output "Stopped API process with PID $pid."
} catch {
    Write-Error "Failed to stop process $pid: $_"
    exit 1
}

Remove-Item $pidFile -ErrorAction SilentlyContinue
