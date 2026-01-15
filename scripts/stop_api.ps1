$repoRoot = Split-Path -Parent $PSScriptRoot
$pidFile = Join-Path $repoRoot "runtime/api.pid"
$statusFile = Join-Path $repoRoot "runtime/state/api.status.json"
$runtimeDir = Join-Path $repoRoot "runtime"
$envFile = Join-Path $runtimeDir ".env"

if (Test-Path -Path $envFile) {
    $env:DOTENV_PATH = $envFile
} else {
    Remove-Item Env:DOTENV_PATH -ErrorAction SilentlyContinue
}

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

function Stop-ListenerProcess {
    param(
        [int]$ProcessId
    )
    if (-not $ProcessId -or $ProcessId -le 0) {
        Write-Error "Refusing to stop invalid PID value."
        $global:LASTEXITCODE = 1
        return $false
    }

    if ($ProcessId -eq $PID) {
        Write-Error "Refusing to stop the current PowerShell PID $PID."
        $global:LASTEXITCODE = 1
        return $false
    }

    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $process) {
        return $true
    }

    if ($process.ProcessName -like "*powershell*") {
        Write-Error "Refusing to stop PowerShell process with PID $ProcessId. PID file may be stale."
        $global:LASTEXITCODE = 1
        return $false
    }

    try {
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        Write-Output "Stopped API listener process with PID $ProcessId."
    } catch {
        $message = "Failed to stop process {0}: {1}" -f $ProcessId, $_
        Write-Error $message
        $global:LASTEXITCODE = 1
        return $false
    }

    return $true
}

$listenerPid = $null
try {
    $listenerPid = Get-ListenerPid -Port ([int]$env:APP_PORT)
} catch {
    Write-Error $_
    $global:LASTEXITCODE = 1
    return
}

$filePid = $null
if (Test-Path $pidFile) {
    try {
        $pidContent = Get-Content -Path $pidFile -Raw -ErrorAction Stop
        $pidValue = $pidContent.Trim()
        $parsedPid = 0
        if ([int]::TryParse($pidValue, [ref]$parsedPid)) {
            $filePid = $parsedPid
        } else {
            Write-Warning "PID file is invalid. Removing it."
        }
    } catch {
        Write-Warning "Could not read PID file."
    }
}

if (-not $listenerPid -and -not $filePid) {
    Write-Warning "No listener PID found for port $($env:APP_PORT) and no valid PID file present."
    Remove-Item $pidFile -ErrorAction SilentlyContinue
    Remove-Item $statusFile -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 0
    return
}

if ($listenerPid -and $filePid -and $listenerPid -ne $filePid) {
    Write-Warning "PID file ($filePid) does not match current listener PID ($listenerPid)."
}

if ($listenerPid) {
    if (-not (Stop-ListenerProcess -ProcessId $listenerPid)) {
        return
    }
} elseif ($filePid) {
    Write-Warning "Listener PID not found; leaving process with PID $filePid untouched."
}

Remove-Item $pidFile -ErrorAction SilentlyContinue
Remove-Item $statusFile -ErrorAction SilentlyContinue
$global:LASTEXITCODE = 0
return
