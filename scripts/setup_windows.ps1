param(
    [string]$PythonExe = "python"
)

Write-Host "[setup] Ensuring virtual environment..."
if (-Not (Test-Path ".venv")) {
    & $PythonExe -m venv .venv
}

$envPath = Join-Path ".venv" "Scripts\Activate.ps1"
. $envPath

Write-Host "[setup] Installing requirements..."
& python -m pip install --upgrade pip
& python -m pip install -r requirements.txt
& python -m pip install -e .

$paths = @("data/state", "data/memory", "data/action_packets", "logs", "gui", "models")
foreach ($p in $paths) {
    if (-Not (Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

# placeholders
"" | Out-File -FilePath "logs/api.log" -Encoding utf8 -Force
"" | Out-File -FilePath "logs/router.log" -Encoding utf8 -Force
"" | Out-File -FilePath "logs/nodes.log" -Encoding utf8 -Force
"" | Out-File -FilePath "logs/audit.jsonl" -Encoding utf8 -Force

if (-Not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Write-Host "[setup] Created .env from example. Please edit signing keys before producing signed packets."
}

Write-Host "[setup] Done. Activate with .\\.venv\\Scripts\\Activate.ps1"
