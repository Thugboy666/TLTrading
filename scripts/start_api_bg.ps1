$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$RuntimeDir = Join-Path $RepoRoot "runtime"
$LogDir = Join-Path $RuntimeDir "logs"
$LogFileOut = Join-Path $LogDir "uvicorn.out.log"
$LogFileErr = Join-Path $LogDir "uvicorn.err.log"
$PidFile = Join-Path $RuntimeDir "api.pid"
$EnvFile = if ($env:DOTENV_PATH) { $env:DOTENV_PATH } else { Join-Path $RuntimeDir ".env" }

if (-not $env:DOTENV_PATH) {
    $env:DOTENV_PATH = $EnvFile
}

Remove-Item Env:PACKET_SIGNING_PRIVATE_KEY_BASE64 -ErrorAction SilentlyContinue
Remove-Item Env:PACKET_SIGNING_PUBLIC_KEY_BASE64  -ErrorAction SilentlyContinue

. "$PSScriptRoot/_load_env.ps1"

$Host = if ($env:APP_HOST) { $env:APP_HOST } else { "127.0.0.1" }
$Port = if ($env:APP_PORT) { $env:APP_PORT } else { "8080" }

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

function Test-ProcessRunning {
    param(
        [int]$ProcessId
    )
    if (-not $ProcessId -or $ProcessId -le 0) {
        return $false
    }

    return (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) -ne $null
}

foreach ($dir in @($RuntimeDir, $LogDir)) {
    if (-Not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

Set-Content -Path $LogFileOut -Value ""
Set-Content -Path $LogFileErr -Value ""

$VenvPython = Join-Path $RepoRoot ".venv\Scripts\python.exe"
if (-not (Test-Path $VenvPython)) {
    Write-Error "Virtualenv python not found at $VenvPython. Run .\\scripts\\bootstrap.ps1 first."
    $global:LASTEXITCODE = 1
    return
}

$existingListenerPid = $null
try {
    $existingListenerPid = Get-ListenerPid -Port ([int]$Port)
} catch {
    Write-Error $_
    $global:LASTEXITCODE = 1
    return
}

if ($existingListenerPid) {
    if (Test-IsUvicornProcess -ProcessId $existingListenerPid) {
        Write-Error "API already running with listener PID $existingListenerPid on port $Port."
    } else {
        Write-Error "Port $Port is already in use by PID $existingListenerPid."
    }
    $global:LASTEXITCODE = 1
    return
}

$arguments = @(
    "-m",
    "uvicorn",
    "thelighttrading.api.server:app",
    "--host",
    $Host,
    "--port",
    $Port
)

$process = Start-Process -FilePath $VenvPython -ArgumentList $arguments -WorkingDirectory $RepoRoot -WindowStyle Hidden -RedirectStandardOutput $LogFileOut -RedirectStandardError $LogFileErr -PassThru

if (-not $process) {
    Write-Error "Failed to start uvicorn process."
    $global:LASTEXITCODE = 1
    return
}

Set-Content -Path $PidFile -Value $process.Id

$healthUri = "http://$Host:${Port}/health"
$ready = $false
for ($attempt = 0; $attempt -lt 120; $attempt++) {
    try {
        $health = Invoke-RestMethod -Uri $healthUri -TimeoutSec 2 -ErrorAction Stop
        if ($health -and $health.ok) {
            $ready = $true
            break
        }
    } catch {
        Start-Sleep -Milliseconds 500
    }
}

if (-not $ready) {
    Write-Error "API failed to become ready at $healthUri within 60 seconds."
    Write-Output "=== Last 80 lines of $LogFileErr ==="
    if (Test-Path $LogFileErr) {
        Get-Content -Path $LogFileErr -Tail 80
    } else {
        Write-Output "(missing log file)"
    }
    Write-Output "=== Last 80 lines of $LogFileOut ==="
    if (Test-Path $LogFileOut) {
        Get-Content -Path $LogFileOut -Tail 80
    } else {
        Write-Output "(missing log file)"
    }

    if (-not (Test-ProcessRunning -ProcessId $process.Id)) {
        Remove-Item -Path $PidFile -ErrorAction SilentlyContinue
    }

    $global:LASTEXITCODE = 1
    return
}

try {
    $apiPid = Get-ListenerPid -Port ([int]$Port)
} catch {
    Write-Error $_
    $global:LASTEXITCODE = 1
    return
}

if (-not $apiPid) {
    Write-Error "API became reachable, but no listener PID found for port $Port."
    $global:LASTEXITCODE = 1
    return
}

if (-not (Test-IsUvicornProcess -ProcessId $apiPid)) {
    Write-Error "API health responded, but port $Port is owned by PID $apiPid which does not appear to be uvicorn."
    $global:LASTEXITCODE = 1
    return
}

Set-Content -Path $PidFile -Value $apiPid

Write-Output "API started with uvicorn PID $apiPid at $healthUri."
$global:LASTEXITCODE = 0
return
