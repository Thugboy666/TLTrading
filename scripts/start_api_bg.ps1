$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeDir = Join-Path $repoRoot "runtime"
$pidFile = Join-Path $runtimeDir "api.pid"
$logDir = Join-Path $runtimeDir "logs"
$logFileOut = Join-Path $logDir "uvicorn.out.log"
$logFileErr = Join-Path $logDir "uvicorn.err.log"
$startScript = Join-Path $PSScriptRoot "start_api.ps1"
$envFile = Join-Path $runtimeDir ".env"

if (Test-Path -Path $envFile) {
    $env:DOTENV_PATH = $envFile
} else {
    Remove-Item Env:DOTENV_PATH -ErrorAction SilentlyContinue
}

Remove-Item Env:PACKET_SIGNING_PRIVATE_KEY_BASE64 -ErrorAction SilentlyContinue
Remove-Item Env:PACKET_SIGNING_PUBLIC_KEY_BASE64  -ErrorAction SilentlyContinue

foreach ($dir in @($runtimeDir, $logDir)) {
    if (-Not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

if (Test-Path $pidFile) {
    try {
        $existingPidContent = Get-Content -Path $pidFile -Raw -ErrorAction Stop
    } catch {
        Write-Warning "Could not read existing PID file."
        $global:LASTEXITCODE = 1
        return
    }

    $existingPidValue = $existingPidContent.Trim()
    $existingPid = 0
    if (-not [int]::TryParse($existingPidValue, [ref]$existingPid)) {
        Write-Warning "Existing PID file is invalid. Removing it."
        Remove-Item $pidFile -ErrorAction SilentlyContinue
    } else {
        $proc = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Warning "API already appears to be running with PID $existingPid. Use scripts/stop_api.ps1 to stop it."
            $global:LASTEXITCODE = 1
            return
        }

        Remove-Item $pidFile -ErrorAction SilentlyContinue
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

Set-Content -Path $pidFile -Value $process.Id
Write-Output "API started in background with PID $($process.Id). Logs: stdout -> $logFileOut, stderr -> $logFileErr"
$global:LASTEXITCODE = 0
return
