$repoRoot = Split-Path -Parent $PSScriptRoot
$pidFile = Join-Path $repoRoot "runtime/api.pid"
$statusFile = Join-Path $repoRoot "runtime/state/api.status.json"

if (-Not (Test-Path $pidFile)) {
    Write-Warning "PID file not found at $pidFile. Nothing to stop."
    $global:LASTEXITCODE = 0
    return
}

try {
    $pidContent = Get-Content -Path $pidFile -Raw -ErrorAction Stop
} catch {
    Write-Warning "Could not read PID file."
    $global:LASTEXITCODE = 1
    return
}

$pidValue = $pidContent.Trim()
$parsedPid = 0
$isValidPid = [int]::TryParse($pidValue, [ref]$parsedPid)
if (-not $isValidPid) {
    Write-Warning "PID file is invalid. Removing it."
    Remove-Item $pidFile -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 1
    return
}

$apiPid = $parsedPid
$process = Get-Process -Id $apiPid -ErrorAction SilentlyContinue
if (-not $process) {
    Write-Warning "No process found with PID $apiPid. Cleaning up PID file."
    Remove-Item $pidFile -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 0
    return
}

if ($process.ProcessName -like "*powershell*") {
    Write-Error "Refusing to stop PowerShell process with PID $apiPid. PID file may be stale."
    $global:LASTEXITCODE = 1
    return
}

try {
    Stop-Process -Id $apiPid -Force -ErrorAction Stop
    Write-Output "Stopped API process with PID $apiPid."
} catch {
    $message = "Failed to stop process {0}: {1}" -f $apiPid, $_
    Write-Error $message
    $global:LASTEXITCODE = 1
    return
}

Remove-Item $pidFile -ErrorAction SilentlyContinue
Remove-Item $statusFile -ErrorAction SilentlyContinue
$global:LASTEXITCODE = 0
return
