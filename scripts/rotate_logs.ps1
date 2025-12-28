$maxSizeBytes = 5MB
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "logs"

Get-ChildItem -Path $logDir -Filter *.log | ForEach-Object {
    if ($_.Length -gt $maxSizeBytes) {
        $newName = "$($logDir)/$($_.BaseName)_$timestamp.log"
        Write-Host "Rotating $($_.Name) -> $newName"
        Move-Item $_.FullName $newName -Force
        "" | Out-File -FilePath $_.FullName -Encoding utf8 -Force
    }
}
