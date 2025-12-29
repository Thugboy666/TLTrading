param(
    [string]$Host = $env:APP_HOST
)

if (-not $Host) {
    $Host = "127.0.0.1"
}

$port = $env:APP_PORT
if (-not $port) {
    $port = "8080"
}

$baseUri = "http://$Host:$port"

function Invoke-Endpoint {
    param(
        [string]$Path,
        [string]$Label
    )

    $uri = "$baseUri$Path"
    try {
        $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -ErrorAction Stop
        Write-Output "[$Label] $uri"
        Write-Output $response.Content
        return $true
    } catch {
        Write-Error "[$Label] request failed: $_"
        return $false
    }
}

$healthOk = Invoke-Endpoint -Path "/health" -Label "Health"
if (-not $healthOk) {
    exit 1
}

$statusOk = Invoke-Endpoint -Path "/status" -Label "Status"
if (-not $statusOk) {
    exit 1
}
