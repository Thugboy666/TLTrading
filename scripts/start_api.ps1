param(
    [switch]$Reload
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeDir = Join-Path $repoRoot "runtime"
$pidFile = Join-Path $runtimeDir "api.pid"
$envFile = Join-Path $runtimeDir ".env"
$envExample = Join-Path $runtimeDir ".env.example"

if (Test-Path -Path $envFile) {
    $env:DOTENV_PATH = $envFile
} else {
    Remove-Item Env:DOTENV_PATH -ErrorAction SilentlyContinue
    if (-not (Test-Path -Path $envExample)) {
        @(
            "APP_HOST=127.0.0.1",
            "APP_PORT=8080",
            "DATA_DIR=./data",
            "LOG_DIR=./logs",
            "LLM_MODE=mock",
            "LLM_BASE_URL=http://127.0.0.1:8081",
            "# PACKET_SIGNING_PRIVATE_KEY_BASE64=",
            "# PACKET_SIGNING_PUBLIC_KEY_BASE64="
        ) | Set-Content -Path $envExample
    }
    Write-Output "runtime/.env not found. Copy runtime/.env.example to runtime/.env and adjust values."
}

Remove-Item Env:PACKET_SIGNING_PRIVATE_KEY_BASE64 -ErrorAction SilentlyContinue
Remove-Item Env:PACKET_SIGNING_PUBLIC_KEY_BASE64  -ErrorAction SilentlyContinue

foreach ($dir in @($runtimeDir, (Join-Path $runtimeDir "data"), (Join-Path $runtimeDir "logs"))) {
    if (-Not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

if (Test-Path $pidFile) {
    $existingPidContent = Get-Content -Path $pidFile -Raw -ErrorAction SilentlyContinue
    $existingPidValue = $existingPidContent.Trim()
    $existingPid = 0
    if ([int]::TryParse($existingPidValue, [ref]$existingPid)) {
        $existingProcess = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
        if ($existingProcess) {
            Write-Warning "API already appears to be running with PID $existingPid. Use scripts/stop_api.ps1 to stop it."
            $global:LASTEXITCODE = 1
            return
        }
    }

    Remove-Item $pidFile -ErrorAction SilentlyContinue
}

$env:DOTENV_PATH = Join-Path $runtimeDir ".env"
. "$PSScriptRoot/_load_env.ps1"

if (-not $env:APP_HOST) { $env:APP_HOST = "127.0.0.1" }
if (-not $env:APP_PORT) { $env:APP_PORT = "8080" }
if (-not $env:DATA_DIR) { $env:DATA_DIR = Join-Path $runtimeDir "data" }
if (-not $env:LOG_DIR) { $env:LOG_DIR = Join-Path $runtimeDir "logs" }

$activateScript = Join-Path $repoRoot ".venv/Scripts/Activate.ps1"
if (-Not (Test-Path $activateScript)) {
    Write-Error "Virtual environment not found. Run scripts/setup_windows.ps1 first."
    $global:LASTEXITCODE = 1
    return
}

. $activateScript
Set-Location $repoRoot

$uvicornArgs = @("-m", "uvicorn", "thelighttrading.api.server:app", "--host", $env:APP_HOST, "--port", $env:APP_PORT)
if ($Reload) { $uvicornArgs += "--reload" }

$uvicornProcess = Start-Process -FilePath "python" -ArgumentList $uvicornArgs -WorkingDirectory $repoRoot -PassThru -NoNewWindow

if (-not $uvicornProcess) {
    Write-Error "Failed to start uvicorn process."
    $global:LASTEXITCODE = 1
    return
}

Set-Content -Path $pidFile -Value $uvicornProcess.Id
Write-Output "API started with uvicorn PID $($uvicornProcess.Id)."
$global:LASTEXITCODE = 0
return
