$repoRoot = Split-Path -Parent $PSScriptRoot
$pidFile = Join-Path $repoRoot "runtime/api.pid"
$uri = "http://127.0.0.1:8080/health"

$expectedPid = $null
$pidFileMissing = $true
if (Test-Path -Path $pidFile) {
    $pidFileMissing = $false
    try {
        $pidContent = Get-Content -Path $pidFile -Raw -ErrorAction Stop
        $pidValue = $pidContent.Trim()
        $parsedPid = 0
        if ([int]::TryParse($pidValue, [ref]$parsedPid)) {
            $expectedPid = $parsedPid
        }
    } catch {
        $pidFileMissing = $true
    }
}

try {
    $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -ErrorAction Stop
} catch {
    Write-Output "DOWN: unable to reach $uri ($_ )"
    exit 1
}

try {
    $health = $response.Content | ConvertFrom-Json
} catch {
    Write-Output "DOWN: invalid JSON response from $uri"
    exit 1
}

if (-not $health) {
    Write-Output "DOWN: empty health response"
    exit 1
}

if (-not $health.ok) {
    Write-Output "DEGRADED: health reported ok=false"
    exit 1
}

if ($pidFileMissing) {
    Write-Output "DEGRADED: PID file missing while health reports ok"
    exit 1
}

if ($expectedPid -and $health.pid -ne $expectedPid) {
    Write-Output "DEGRADED: PID mismatch (expected $expectedPid, got $($health.pid))"
    exit 1
}

Write-Output "OK: pid $($health.pid) uptime $($health.uptime_seconds)s mode $($health.llm_mode)"
exit 0
