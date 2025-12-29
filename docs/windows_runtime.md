# Windows runtime helpers

Use the PowerShell helpers in `scripts/` to keep the runtime environment isolated from any stray global variables.

The runtime layout expected by the scripts is:

```
runtime/
  bin/llama/       # llama.cpp server.exe lives here (download manually)
  models/chat/     # chat GGUF models (LLAMA_CHAT_MODEL defaults to chat.gguf)
  models/embed/    # optional embedding GGUF models
  logs/            # stdout/stderr for API + LLM
```

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

## Run llama.cpp server in background and stop it

```powershell
# assumes runtime/bin/llama/server.exe exists and a GGUF at runtime/models/chat/chat.gguf
scripts\start_llm_bg.ps1 -ModelPath runtime/models/chat/chat.gguf
scripts\stop_llm.ps1
```

The LLM helper writes `runtime/llama.pid` and logs stdout/stderr to `runtime/logs/llama.*.log`. The script clears stray `PACKET_SIGNING_*` variables and refuses to kill the current PowerShell session if the PID file is stale.

## Quick health check

```powershell
# API only
scripts\health_check.ps1

# API + llama.cpp
scripts\health_check.ps1 -CheckLlm
```
