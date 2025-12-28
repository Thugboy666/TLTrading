. "$PSScriptRoot/_load_env.ps1"

if (-not $env:APP_HOST) { $env:APP_HOST = "127.0.0.1" }
if (-not $env:APP_PORT) { $env:APP_PORT = "8080" }

. "$PSScriptRoot/../.venv/Scripts/Activate.ps1"
& python -m uvicorn thelighttrading.api.server:app --host $env:APP_HOST --port $env:APP_PORT
