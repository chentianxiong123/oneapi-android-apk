#!/usr/bin/env pwsh
# Download One API v0.6.10 arm64 binary
$url = "https://github.com/songquanpeng/one-api/releases/download/v0.6.10/one-api-arm64"
$out = Join-Path $PSScriptRoot "app/src/main/jniLibs/arm64-v8a/liboneapi.so"

if (Test-Path $out) { Write-Output "Already exists"; exit }

Write-Output "Downloading One API arm64..."
$wc = New-Object System.Net.WebClient
$wc.DownloadFile($url, $out)
Write-Output "Saved: $out ($((Get-Item $out).Length/1MB) MB)"
