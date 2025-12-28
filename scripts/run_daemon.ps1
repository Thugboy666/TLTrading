. "$PSScriptRoot/_load_env.ps1"

$venvPath = "$PSScriptRoot/../.venv/Scripts/Activate.ps1"
if (Test-Path $venvPath) {
    . $venvPath
}

$interval = 60
if ($args.Length -gt 0) {
    $interval = [int]$args[0]
}

Write-Host "Starting scheduler with interval $interval seconds..."
python -m thelighttrading.cli.main run-daemon --interval $interval
