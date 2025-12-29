# Windows runtime helpers

Use the PowerShell helpers in `scripts/` to keep the runtime environment isolated from any stray global variables.

## Prepare environment

```powershell
# from the repository root
Copy-Item runtime/.env.example runtime/.env
```

The `runtime/.env` file is the single source of truth for local environment variables.

## Run API in foreground

```powershell
scripts\start_api.ps1
```

The script clears any lingering `PACKET_SIGNING_*` variables in the current session, ensures `runtime/`, `data/`, and `logs/` exist, and then delegates to `scripts/run_api.ps1`.

## Health check

```powershell
scripts\health_check.ps1
```

This issues a GET request to `http://127.0.0.1:8080/health` and exits with a non-zero code if unreachable.

## Run API in background and stop it

```powershell
scripts\start_api_bg.ps1
scripts\stop_api.ps1
```

Background runs write a PID file to `runtime/api.pid` and log output to `logs/uvicorn.log`.
