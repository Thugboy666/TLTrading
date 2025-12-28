# Architecture

The system uses a node-based pipeline orchestrated in Python:

1. **NewsNode** (`news_llama`): summarizes market news.
2. **ParserNode** (`parser_qwen`): transforms summaries into strict JSON signals.
3. **BrainNode** (`brain_mistral`): crafts strategy JSON from signals.
4. **WatchdogNode** (`watchdog_phi`): evaluates risk and may block actions.
5. **PacketNode**: builds an ActionPacket with anti-replay and policy_hash safeguards.

Each node runs through the LLM router which supports **mock** and **real** modes. Real mode calls an OpenAI-compatible llama.cpp server; mock mode returns deterministic strings for tests.

Persistent storage:
- Node memory: SQLite `data/memory/thelighttrading.db`
- Replay protection: `data/state/replay_state.json`
- Runs: `data/state/runs/<run_id>.json`

ActionPackets are signed with Ed25519 using PyNaCl when keys are available. Missing keys yield HOLD UNSIGNED packets.
