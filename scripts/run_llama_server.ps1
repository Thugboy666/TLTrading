# Guidance only: configure and launch your llama.cpp HTTP server manually.
# Example (adjust paths/models):
# .\server.exe -m .\models\your_model.gguf --port 8081 --host 127.0.0.1 --chat
# Ensure the server exposes an OpenAI-compatible /v1/chat/completions endpoint.
Write-Host "Start your llama.cpp server separately and set LLM_MODE=local with LLM_HOST=127.0.0.1 and LLM_PORT=8081"
