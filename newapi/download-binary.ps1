#!/usr/bin/env pwsh
# Download New API v1.0.0-rc.15 arm64 binary
$url = "https://github.com/QuantumNous/new-api/releases/download/v1.0.0-rc.15/new-api-arm64-v1.0.0-rc.15"
$out = Join-Path $PSScriptRoot "app/src/main/jniLibs/arm64-v8a/liboneapi.so"

if (Test-Path $out) { Write-Output "Already exists"; exit }

Write-Output "Downloading New API arm64..."
$wc = New-Object System.Net.WebClient
$wc.DownloadFile($url, $out)
Write-Output "Saved: $out ($((Get-Item $out).Length/1MB) MB)"
