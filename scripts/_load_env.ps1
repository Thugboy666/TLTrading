$repoRoot = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $repoRoot ".env"

if (-Not (Test-Path -Path $envFile)) {
    return
}

foreach ($rawLine in Get-Content -Path $envFile) {
    $line = $rawLine.Trim()
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
        continue
    }

    $parts = $line.Split('=', 2)
    if ($parts.Count -lt 2) {
        continue
    }

    $key = $parts[0].Trim()
    $value = $parts[1].Trim()

    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
        $value = $value.Substring(1, $value.Length - 2)
    }

    if (-Not [string]::IsNullOrEmpty($key)) {
        [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
    }
}
