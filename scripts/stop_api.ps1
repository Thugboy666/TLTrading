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

function Get-ListeningPids {
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
            $netstatLines = netstat -ano | findstr ":${Port}"
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

    return ($pids | Where-Object { $_ -ne $null } | Select-Object -Unique)
}

function Get-ProcessDetails {
    param(
        [int]$ProcessId
    )
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $process) {
        return $null
    }

    $commandLine = $null
    try {
        $commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId").CommandLine
    } catch {
        $commandLine = $null
    }

    $startTime = $null
    try {
        $startTime = $process.StartTime
    } catch {
        $startTime = $null
    }

    return [pscustomobject]@{
        Id = $ProcessId
        Name = $process.ProcessName
        CommandLine = $commandLine
        StartTime = $startTime
    }
}

function Select-ListenerPid {
    param(
        [int[]]$CandidatePids
    )
    if (-not $CandidatePids -or $CandidatePids.Count -eq 0) {
        return $null
    }

    $uniquePids = $CandidatePids | Select-Object -Unique
    $processInfos = @()
    foreach ($pidValue in $uniquePids) {
        $info = Get-ProcessDetails -ProcessId $pidValue
        if ($info) {
            $processInfos += $info
        }
    }

    if (-not $processInfos -or $processInfos.Count -eq 0) {
        return ($uniquePids | Select-Object -First 1)
    }

    $uvicornInfos = $processInfos | Where-Object {
        ($_.CommandLine -match "uvicorn") -or ($_.CommandLine -match "thelighttrading.api.server")
    }

    $candidateInfos = $uvicornInfos
    if (-not $candidateInfos -or $candidateInfos.Count -eq 0) {
        $candidateInfos = $processInfos
    }

    $selected = $candidateInfos | Sort-Object -Property @{Expression = { if ($_.StartTime) { $_.StartTime } else { [datetime]::MinValue } }} -Descending | Select-Object -First 1
    return $selected.Id
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
            Remove-Item $pidFile -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Warning "Could not read PID file."
    }
}

if ($filePid) {
    $fileProcess = Get-Process -Id $filePid -ErrorAction SilentlyContinue
    if ($fileProcess) {
        if (-not (Stop-ListenerProcess -ProcessId $filePid)) {
            return
        }
        Remove-Item $pidFile -ErrorAction SilentlyContinue
        Remove-Item $statusFile -ErrorAction SilentlyContinue
        $global:LASTEXITCODE = 0
        return
    }
    Write-Warning "PID file ($filePid) is stale; falling back to port discovery."
    Remove-Item $pidFile -ErrorAction SilentlyContinue
}

$listenerPids = Get-ListeningPids -Port ([int]$env:APP_PORT)
if (-not $listenerPids -or $listenerPids.Count -eq 0) {
    Write-Warning "No listener PID found for port $($env:APP_PORT)."
    Remove-Item $statusFile -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 0
    return
}

$selectedPid = Select-ListenerPid -CandidatePids $listenerPids
if (-not $selectedPid) {
    Write-Warning "Unable to select a listener PID for port $($env:APP_PORT)."
    $global:LASTEXITCODE = 1
    return
}

if (-not (Stop-ListenerProcess -ProcessId $selectedPid)) {
    return
}

Remove-Item $pidFile -ErrorAction SilentlyContinue
Remove-Item $statusFile -ErrorAction SilentlyContinue
$global:LASTEXITCODE = 0
return
