. "$PSScriptRoot/_load_env.ps1"

if (-not $env:APP_HOST) { $env:APP_HOST = "127.0.0.1" }
if (-not $env:APP_PORT) { $env:APP_PORT = "8080" }

$venvPath = "$PSScriptRoot/../.venv/Scripts/Activate.ps1"
if (Test-Path $venvPath) {
    . $venvPath
}

Write-Host "Starting API server..."
Start-Process -FilePath "powershell" -ArgumentList "-NoProfile", "-Command", "& '$PSScriptRoot/run_api.ps1'"

$baseUrl = "http://$env:APP_HOST`:$env:APP_PORT"
Write-Host "UI: $baseUrl/"
Write-Host "Docs: $baseUrl/docs"
Write-Host "Status: $baseUrl/status"
Write-Host "Metrics: $baseUrl/metrics"
Write-Host "Inputs: $baseUrl/inputs/status"

Start-Process $baseUrl/
