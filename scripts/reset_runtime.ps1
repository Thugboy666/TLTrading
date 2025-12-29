$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeDir = Join-Path $repoRoot "runtime"
$pidFile = Join-Path $runtimeDir "api.pid"
$dataDir = Join-Path $runtimeDir "data"
$logsDir = Join-Path $runtimeDir "logs"
$envFile = Join-Path $runtimeDir ".env"
$envExample = Join-Path $runtimeDir ".env.example"

if (-not (Test-Path $runtimeDir)) {
    New-Item -ItemType Directory -Path $runtimeDir | Out-Null
}

if (Test-Path $pidFile) {
    Remove-Item $pidFile -ErrorAction SilentlyContinue
}

foreach ($dir in @($dataDir, $logsDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
        continue
    }

    Get-ChildItem -Path $dir -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
}

foreach ($dir in @($dataDir, $logsDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

foreach ($file in @($envFile, $envExample)) {
    if (Test-Path $file) {
        Write-Verbose "Preserved $file"
    }
}

Write-Output "Runtime state cleared. Logs and data under runtime/ have been reset."
