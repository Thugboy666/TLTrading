$repoRoot = Split-Path -Parent $PSScriptRoot
$pidFile = Join-Path $repoRoot "runtime/api.pid"

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

$pid = $parsedPid
$process = Get-Process -Id $pid -ErrorAction SilentlyContinue
if (-not $process) {
    Write-Warning "No process found with PID $pid. Cleaning up PID file."
    Remove-Item $pidFile -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 0
    return
}

if ($process.ProcessName -like "*powershell*") {
    Write-Error "Refusing to stop PowerShell process with PID $pid. PID file may be stale."
    $global:LASTEXITCODE = 1
    return
}

try {
    Stop-Process -Id $pid -Force -ErrorAction Stop
    Write-Output "Stopped API process with PID $pid."
} catch {
    $message = "Failed to stop process {0}: {1}" -f $pid, $_
    Write-Error $message
    $global:LASTEXITCODE = 1
    return
}

Remove-Item $pidFile -ErrorAction SilentlyContinue
$global:LASTEXITCODE = 0
return
