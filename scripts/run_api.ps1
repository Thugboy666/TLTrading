. .\.venv\Scripts\Activate.ps1
& uvicorn thelighttrading.api.server:app --host $env:APP_HOST --port $env:APP_PORT
