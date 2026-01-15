$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeDir = Join-Path $repoRoot "runtime"
$logDir = Join-Path $runtimeDir "logs"
$logFileOut = Join-Path $logDir "uvicorn.out.log"
$logFileErr = Join-Path $logDir "uvicorn.err.log"
$startScript = Join-Path $PSScriptRoot "start_api.ps1"
$envFile = Join-Path $runtimeDir ".env"
$pidFile = Join-Path $runtimeDir "api.pid"
$wrapperPidFile = Join-Path $runtimeDir "api.wrapper.pid"

if (Test-Path -Path $envFile) {
    $env:DOTENV_PATH = $envFile
} else {
    Remove-Item Env:DOTENV_PATH -ErrorAction SilentlyContinue
}

Remove-Item Env:PACKET_SIGNING_PRIVATE_KEY_BASE64 -ErrorAction SilentlyContinue
Remove-Item Env:PACKET_SIGNING_PUBLIC_KEY_BASE64  -ErrorAction SilentlyContinue

. "$PSScriptRoot/_load_env.ps1"

if (-not $env:APP_HOST) { $env:APP_HOST = "127.0.0.1" }
if (-not $env:APP_PORT) { $env:APP_PORT = "8080" }

function Get-ListenerPid {
    param(
        [int]$Port
    )
    $pids = @()
    $netTcpCommand = Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue
    if ($netTcpCommand) {
        try {
            $connections = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop
            $pids = $connections | Select-Object -ExpandProperty OwningProcess
        } catch {
            $pids = @()
        }
    }

    if (-not $pids -or $pids.Count -eq 0) {
        try {
            $netstatLines = netstat -ano | findstr ":$Port"
            foreach ($line in $netstatLines) {
                if ($line -match "LISTENING" -or $line -match "LISTEN") {
                    $parts = $line -split "\s+"
                    $pidValue = $parts[-1]
                    $parsedPid = 0
                    if ([int]::TryParse($pidValue, [ref]$parsedPid)) {
                        $pids += $parsedPid
                    }
                }
            }
        } catch {
            $pids = @()
        }
    }

    $uniquePids = $pids | Where-Object { $_ -ne $null } | Select-Object -Unique
    if ($uniquePids.Count -gt 1) {
        throw "Multiple listening PIDs found for port ${Port}: $($uniquePids -join ', ')."
    }
    if ($uniquePids.Count -eq 1) {
        return $uniquePids[0]
    }
    return $null
}

function Test-IsUvicornProcess {
    param(
        [int]$ProcessId
    )
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $process) {
        return $false
    }

    $commandLine = $null
    try {
        $commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId").CommandLine
    } catch {
        $commandLine = $null
    }

    if ($commandLine) {
        return ($commandLine -match "uvicorn") -or ($commandLine -match "thelighttrading.api.server")
    }

    return $process.ProcessName -match "python|uvicorn"
}

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

$existingListenerPid = $null
try {
    $existingListenerPid = Get-ListenerPid -Port ([int]$env:APP_PORT)
} catch {
    Write-Error $_
    $global:LASTEXITCODE = 1
    return
}

if ($existingListenerPid) {
    if (Test-IsUvicornProcess -ProcessId $existingListenerPid) {
        Write-Error "API already running with listener PID $existingListenerPid on port $($env:APP_PORT)."
    } else {
        Write-Error "Port $($env:APP_PORT) is already in use by PID $existingListenerPid."
    }
    $global:LASTEXITCODE = 1
    return
}

$process = Start-Process -FilePath "powershell" -ArgumentList $arguments -WorkingDirectory $repoRoot -PassThru

if (-not $process) {
    Write-Error "Failed to start API in background."
    $global:LASTEXITCODE = 1
    return
}

Set-Content -Path $wrapperPidFile -Value $process.Id
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
    if ($process -and $process.Id -ne $PID) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    $global:LASTEXITCODE = 1
    return
}

try {
    $apiPid = Get-ListenerPid -Port ([int]$env:APP_PORT)
} catch {
    Write-Error $_
    $global:LASTEXITCODE = 1
    return
}

if (-not $apiPid) {
    Write-Error "API became reachable, but no listener PID found for port $($env:APP_PORT)."
    $global:LASTEXITCODE = 1
    return
}

if (-not (Test-IsUvicornProcess -ProcessId $apiPid)) {
    Write-Error "API health responded, but port $($env:APP_PORT) is owned by PID $apiPid which does not appear to be uvicorn."
    $global:LASTEXITCODE = 1
    return
}

Set-Content -Path $pidFile -Value $apiPid

Write-Output "API wrapper PID: $($process.Id)"
Write-Output "API listener PID: $apiPid"
Write-Output "API ready at $healthUri."
$global:LASTEXITCODE = 0
return
