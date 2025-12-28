# Guidance only: configure and launch your llama.cpp HTTP server manually.
# Example (adjust paths/models):
# .\server.exe -m .\models\your_model.gguf --port 8081 --host 127.0.0.1 --chat
# Ensure the server exposes an OpenAI-compatible /v1/chat/completions endpoint.
Write-Host "Start your llama.cpp server separately and set LLM_MODE=real with LLM_BASE_URL=http://127.0.0.1:8081"
