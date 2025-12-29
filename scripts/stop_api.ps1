$repoRoot = Split-Path -Parent $PSScriptRoot
$pidFile = Join-Path $repoRoot "runtime/api.pid"

if (-Not (Test-Path $pidFile)) {
    Write-Warning "PID file not found at $pidFile. Nothing to stop."
    exit 0
}

try {
    $pidContent = Get-Content -Path $pidFile -Raw -ErrorAction Stop
} catch {
    Write-Warning "Could not read PID file."
    exit 1
}

$pidValue = $pidContent.Trim()
$parsedPid = 0
$isValidPid = [int]::TryParse($pidValue, [ref]$parsedPid)
if (-not $isValidPid) {
    Write-Warning "PID file is invalid. Removing it."
    Remove-Item $pidFile -ErrorAction SilentlyContinue
    exit 1
}

$pid = $parsedPid
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
    $message = "Failed to stop process {0}: {1}" -f $pid, $_
    Write-Error $message
    exit 1
}

Remove-Item $pidFile -ErrorAction SilentlyContinue
