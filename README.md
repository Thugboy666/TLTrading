# TheLightTrading

TheLightTrading is a Windows-first prototype for multi-LLM trading research. It ships with a node-based pipeline, per-node persistent memory, llama.cpp integration, and a minimal Three.js GUI. The repository is self-contained; LLM models are external GGUF files and not committed.

## Quick start (Windows PowerShell)

```powershell
# one-time setup
scripts\setup_windows.ps1

# run API (localhost:8080) and GUI (served from the same port)
scripts\run_api.ps1
scripts\run_gui.ps1

# run pipeline via CLI
thelighttrading run-pipeline

# run smoke tests
scripts\smoke_test.ps1
```

Copy `.env.example` to `.env` and provide signing keys if you want signed ActionPackets. Without keys, the system generates HOLD packets marked UNSIGNED.

## Modes
- `LLM_MODE=mock` (default): deterministic mock outputs suitable for tests.
- `LLM_MODE=real`: sends OpenAI-compatible chat requests to a llama.cpp server at `LLM_BASE_URL`.

## Pipeline
1. NewsNode (news_llama) → summary
2. ParserNode (parser_qwen) → structured signals
3. BrainNode (brain_mistral) → strategy JSON
4. WatchdogNode (watchdog_phi) → risk gate
5. PacketNode → ActionPacket signing/validation with anti-replay

Runs are stored under `data/state/runs/<run_id>.json`. Node memories persist in `data/memory/thelighttrading.db`.

## GUI
Open `http://127.0.0.1:8080` to view the node graph and run the pipeline. The GUI communicates with the FastAPI backend and displays last node outputs.

## Tests
Run `pytest` (defaults to mock LLM mode). CI enforces these tests.

## Safety
ActionPackets include policy hashes, nonces, sequences, expiries, and Ed25519 signatures when keys are supplied. Missing keys cause HOLD UNSIGNED packets for safety.
