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

if (!(Test-Path $logFileOut)) { "" | Out-File -FilePath $logFileOut -Encoding utf8 -Force }
if (!(Test-Path $logFileErr)) { "" | Out-File -FilePath $logFileErr -Encoding utf8 -Force }

$process = Start-Process -FilePath "powershell" -ArgumentList @("-NoLogo", "-NoProfile", "-File", "`"$startScript`"") -WorkingDirectory $repoRoot -RedirectStandardOutput $logFileOut -RedirectStandardError $logFileErr -PassThru

if (-not $process) {
    Write-Error "Failed to start API in background."
    exit 1
}

Set-Content -Path $pidFile -Value $process.Id
Write-Output "API started in background with PID $($process.Id). Logs: stdout -> $logFileOut, stderr -> $logFileErr"
