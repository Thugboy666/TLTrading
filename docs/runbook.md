# Runbook

## Setup
- Use PowerShell on Windows.
- Execute `scripts/setup_windows.ps1` to create the virtual environment, install dependencies, and generate `.env`.
- Edit `.env` to provide signing keys if you want signed packets.

## Running
- API: `scripts/run_api.ps1`
- GUI: `scripts/run_gui.ps1` (opens default browser)
- All-in-one: `scripts/run_all.ps1`
- Smoke tests: `scripts/smoke_test.ps1`

## llama.cpp server
Use `scripts/run_llama_server.ps1` for guidance on starting a llama.cpp HTTP server. No downloads are automated.

## Logs
Logs live in `logs/`. Use `scripts/rotate_logs.ps1` to rotate files larger than 5MB.
