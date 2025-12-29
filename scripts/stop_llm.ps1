$repoRoot = Split-Path -Parent $PSScriptRoot
$pidFile = Join-Path $repoRoot "runtime/llama.pid"

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
$llmPid = 0
$isValidPid = [int]::TryParse($pidValue, [ref]$llmPid)
if (-not $isValidPid) {
    Write-Warning "PID file is invalid. Removing it."
    Remove-Item $pidFile -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 1
    return
}

if ($llmPid -eq $PID) {
    Write-Error "Refusing to stop the current PowerShell process (PID $PID). PID file may be stale."
    $global:LASTEXITCODE = 1
    return
}

$process = Get-Process -Id $llmPid -ErrorAction SilentlyContinue
if (-not $process) {
    Write-Warning "No process found with PID $llmPid. Cleaning up PID file."
    Remove-Item $pidFile -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 0
    return
}

if ($process.ProcessName -like "*powershell*") {
    Write-Error "Refusing to stop PowerShell process with PID $llmPid. PID file may be stale."
    $global:LASTEXITCODE = 1
    return
}

try {
    Stop-Process -Id $llmPid -Force -ErrorAction Stop
    Write-Output "Stopped LLM server process with PID $llmPid."
} catch {
    $message = "Failed to stop process {0}: {1}" -f $llmPid, $_
    Write-Error $message
    $global:LASTEXITCODE = 1
    return
}

Remove-Item $pidFile -ErrorAction SilentlyContinue
$global:LASTEXITCODE = 0
return
