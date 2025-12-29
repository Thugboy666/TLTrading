$uri = "http://127.0.0.1:8080/health"
try {
    $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -ErrorAction Stop
    Write-Output $response.Content
} catch {
    Write-Error "Health check failed: $_"
    exit 1
}
