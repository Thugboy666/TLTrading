. "$PSScriptRoot/_load_env.ps1"

$host = if ($env:APP_HOST) { $env:APP_HOST } else { "127.0.0.1" }
$port = if ($env:APP_PORT) { $env:APP_PORT } else { "8080" }

Start-Process "http://$host`:$port/"
