. "$PSScriptRoot/_load_env.ps1"

$venvPath = "$PSScriptRoot/../.venv/Scripts/Activate.ps1"
if (Test-Path $venvPath) {
    . $venvPath
}

Write-Host "Generating packet signing keypair..."
$cmd = "python -m thelighttrading.cli.main gen-keys"
Invoke-Expression $cmd
Write-Host "Paste the values into your .env or use --out .env.local to write automatically."
