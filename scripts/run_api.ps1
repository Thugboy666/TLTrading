. .\.venv\Scripts\Activate.ps1
& python -m uvicorn thelighttrading.api.server:app --host $env:APP_HOST --port $env:APP_PORT
