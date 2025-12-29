$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeDir = Join-Path $repoRoot "runtime"
$logDir = Join-Path $runtimeDir "logs"
$logFileOut = Join-Path $logDir "uvicorn.out.log"
$logFileErr = Join-Path $logDir "uvicorn.err.log"
$startScript = Join-Path $PSScriptRoot "start_api.ps1"

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
$global:LASTEXITCODE = 0
return
