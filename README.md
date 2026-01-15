# TheLightTrading

TheLightTrading is a Windows-first prototype for multi-LLM trading research. It ships with a node-based pipeline, per-node persistent memory, llama.cpp integration, and a minimal Three.js GUI. The repository is self-contained; LLM models are external GGUF files and not committed.

## Quick start (Windows PowerShell)

```powershell
# one-time setup
scripts\setup_windows.ps1

# bootstrap runtime (creates runtime/.env.example if missing)
scripts\reset_runtime.ps1
Copy-Item runtime/.env.example runtime/.env -ErrorAction SilentlyContinue

# manually download llama.cpp (rpc-server.exe or server.exe) into runtime/bin/llama
# place chat GGUF model under runtime/models/chat (for example chat.gguf)
# optional: place embedding model under runtime/models/embed

# start LLM server in background (defaults to http://127.0.0.1:8081)
# model selection prefers LLM_CHAT_MODEL, then LOCAL_CHAT_MODEL_DEFAULT, then other LOCAL_CHAT_* entries, then first GGUF in runtime/models/chat
scripts\start_llm_bg.ps1

# start API in background (defaults to http://127.0.0.1:8080) and check status
scripts\start_api_bg.ps1
scripts\status_check.ps1
scripts\health_check.ps1 -CheckLlm
# or: curl http://127.0.0.1:8080/llm/health

# stop API when finished
scripts\stop_api.ps1
# stop LLM server when finished
scripts\stop_llm.ps1

# run GUI (served from the same API port)
scripts\run_gui.ps1

# run pipeline via CLI
thelighttrading run-pipeline

# run smoke tests
scripts\smoke_test.ps1
```

## Portable mode (Windows, embeddable Python)

Portable mode uses the official Python embeddable distribution placed at `runtime/python/python.exe`. Download the **Windows embeddable package (64-bit)** from the Python Windows downloads page and extract the zip contents into `runtime/python/` so that `runtime/python/python.exe` exists.

- Python downloads: https://www.python.org/downloads/windows/

First-time portable setup:

```powershell
scripts\bootstrap_portable.ps1
scripts\portable_shell.ps1
```

Portable run order (after opening the portable shell):

```powershell
scripts\start_llm_bg.ps1
scripts\start_api_bg.ps1
scripts\health_check.ps1 -CheckLlm
```

Copy `runtime/.env.example` to `runtime/.env` and provide signing keys if you want signed ActionPackets. Without keys, the system generates HOLD packets marked UNSIGNED.

Recommended llama.cpp settings in `runtime/.env`:

```
LLM_MODE=local
LLM_HOST=127.0.0.1
LLM_PORT=8081
LLM_CHAT_MODEL=runtime/models/chat/mistral-7b-instruct-v0.2.Q4_K_M.gguf
LLM_EMBED_MODEL=runtime/models/embed/e5-base-v2.Q4_K_M.gguf
```

Start order for local mode:

```
scripts\start_llm_bg.ps1
scripts\start_api_bg.ps1
curl http://127.0.0.1:8080/llm/health
```

See `docs/windows_runtime.md` for background start/stop helpers and additional notes.

## Local LLM runtime layout

```
runtime/
  bin/llama/       # copy the llama.cpp release folder here (rpc-server.exe or server.exe)
  models/chat/     # place chat GGUF models here
  models/embed/    # optional: embedding GGUF models
  logs/            # captured stdout/stderr for API and LLM servers
  state/           # PID/status files
```

The PowerShell scripts read `runtime/.env` when it exists and will not overwrite it. Configure model filenames with `LLM_CHAT_MODEL` (preferred) or `LOCAL_CHAT_MODEL_DEFAULT`, `LOCAL_CHAT_MODEL_QWEN`, `LOCAL_CHAT_MODEL_MISTRAL`, and `LOCAL_EMBED_MODEL`. Point `LLM_HOST` and `LLM_PORT` at your llama.cpp server. `scripts/start_llm_bg.ps1` auto-detects `rpc-server.exe`/`server.exe`, adds `--log-disable` only when supported, and honors `LLM_THREADS` for `-t` when set. Update `LLM_MODE=local` after launching the llama.cpp server with `scripts/start_llm_bg.ps1`.

To stop and start the stack:

```powershell
scripts\stop_llm.ps1
scripts\start_llm_bg.ps1
scripts\start_api.ps1
curl http://127.0.0.1:8080/llm/health
```

Models live under `runtime/models/chat` and `runtime/models/embed`. Place the entire unpacked llama.cpp Windows release (including `rpc-server.exe`, `server.exe`, or any `*server*.exe`) inside `runtime/bin/llama/` so the scripts can move with the repository without reconfiguration. Point the env vars above at your GGUF filenames; relative paths are resolved from the repo root at runtime.

## Modes
- `LLM_MODE=mock` (default): deterministic mock outputs suitable for tests.
- `LLM_MODE=local`: sends OpenAI-compatible chat requests to llama.cpp running at `LLM_HOST` / `LLM_PORT`.

## Pipeline
1. NewsNode (news_llama) → summary
2. ParserNode (parser_qwen) → structured signals
3. BrainNode (brain_mistral) → strategy JSON
4. WatchdogNode (watchdog_phi) → risk gate
5. PacketNode → ActionPacket signing/validation with anti-replay

Runs are stored under `data/state/runs/<run_id>.json`. Node memories persist in `data/memory/thelighttrading.db`.

## GUI
Open `http://127.0.0.1:8080` (the API port) to view the node graph and run the pipeline. The GUI communicates with the FastAPI backend and displays last node outputs.

## Tests
Run `pytest` (defaults to mock LLM mode). CI enforces these tests.

## Safety
ActionPackets include policy hashes, nonces, sequences, expiries, and Ed25519 signatures when keys are supplied. Missing keys cause HOLD UNSIGNED packets for safety.
