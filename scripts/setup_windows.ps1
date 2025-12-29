param(
    [string]$PythonExe = "python"
)

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$venvPath = Join-Path $repoRoot ".venv"
$activateScript = Join-Path $venvPath "Scripts/Activate.ps1"
$venvPython = Join-Path $venvPath "Scripts/python.exe"

Write-Host "[setup] Ensuring virtual environment..."
if (-Not (Test-Path $venvPath)) {
    & $PythonExe -m venv $venvPath
}

if (-Not (Test-Path $activateScript)) {
    Write-Error "Virtual environment activation script not found at $activateScript"
    exit 1
}

. $activateScript

if (-Not (Test-Path $venvPython)) {
    Write-Error "Virtual environment python executable not found at $venvPython"
    exit 1
}

Write-Host "[setup] Installing requirements..."
& $venvPython -m pip install --upgrade pip
& $venvPython -m pip install -r requirements.txt
& $venvPython -m pip install -e .

$runtimeRoot = Join-Path $repoRoot "runtime"
$dataDir = Join-Path $runtimeRoot "data"
$logsDir = Join-Path $runtimeRoot "logs"
$inputsDir = Join-Path $dataDir "inputs"

$paths = @(
    $dataDir,
    (Join-Path $dataDir "state"),
    (Join-Path $dataDir "memory"),
    (Join-Path $dataDir "action_packets"),
    $inputsDir,
    $logsDir,
    (Join-Path $repoRoot "gui"),
    (Join-Path $repoRoot "models")
)

foreach ($p in $paths) {
    if (-Not (Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

$sampleHeadlines = @(
    "Breaking: Contoso beats earnings expectations",
    "Fabrikam announces new product line",
    "Northwind shares rise on merger rumors"
)
$sampleHeadlines -join "`n" | Out-File -FilePath (Join-Path $inputsDir "headlines.txt") -Encoding utf8 -Force

"" | Out-File -FilePath (Join-Path $logsDir "api.log") -Encoding utf8 -Force
"" | Out-File -FilePath (Join-Path $logsDir "router.log") -Encoding utf8 -Force
"" | Out-File -FilePath (Join-Path $logsDir "nodes.log") -Encoding utf8 -Force
"" | Out-File -FilePath (Join-Path $logsDir "audit.jsonl") -Encoding utf8 -Force

if (-Not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Write-Host "[setup] Created .env from example. Please edit signing keys before producing signed packets."
}

Write-Host "[setup] Done. Activate with .\\.venv\\Scripts\\Activate.ps1"
