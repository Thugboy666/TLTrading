$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$portablePython = Join-Path $repoRoot "runtime/python/python.exe"
if (-Not (Test-Path $portablePython)) {
    Write-Error "Portable Python not found at $portablePython. Download the Windows embeddable zip and extract to runtime/python/."
    exit 1
}

$venvPath = Join-Path $repoRoot ".venv"
$activateScript = Join-Path $venvPath "Scripts/Activate.ps1"
$venvPython = Join-Path $venvPath "Scripts/python.exe"

Write-Host "[portable] Ensuring virtual environment..."
if (-Not (Test-Path $venvPath)) {
    & $portablePython -m venv $venvPath
}

if (-Not (Test-Path $venvPython)) {
    Write-Error "Virtual environment python executable not found at $venvPython"
    exit 1
}

Write-Host "[portable] Installing requirements..."
& $venvPython -m pip install --upgrade pip
& $venvPython -m pip install -r requirements.txt
& $venvPython -m pip install -e .

Write-Host "[portable] Done. Activate with .\\.venv\\Scripts\\Activate.ps1"
