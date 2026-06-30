#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Cross-compile New API Go source and build Android APK.
.DESCRIPTION
    Two build modes:
      - Without frontend (-Tags no_web): ~52MB binary, fastest, for benchmarking / headless
      - With frontend    (default):       ~127MB binary, full admin dashboard
.PARAMETER Tags
    Go build tags. Use "no_web" to exclude frontend (smaller binary).
    Omit for full build with embedded frontend.
.PARAMETER OutDir
    Output directory for compiled .so (default: app/src/main/jniLibs/arm64-v8a/).
.PARAMETER SkipGradle
    If set, only cross-compile the Go binary, skip APK packaging.
.EXAMPLE
    # Build without frontend (fast, small)
    ./build_from_source.ps1 -Tags no_web

    # Build with full frontend
    ./build_from_source.ps1

    # Cross-compile only, no APK
    ./build_from_source.ps1 -Tags no_web -SkipGradle
#>

param(
    [string]$Tags = "",
    [string]$OutDir = "app/src/main/jniLibs/arm64-v8a",
    [switch]$SkipGradle
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
$GoSrc = Join-Path $ScriptDir "go-source"

if (-not (Test-Path $GoSrc)) {
    Write-Error "Go source not found at $GoSrc. Make sure go-source/ exists with the full new-api source tree."
    exit 1
}

# Stage 1 — Cross-compile Go → Android arm64 .so
Write-Output "=== Stage 1: Cross-compile Go binary ==="
$env:GOOS = "android"
$env:GOARCH = "arm64"
$env:CGO_ENABLED = "0"
$env:GOARM = ""

$tagArg = if ($Tags) { "-tags $Tags" } else { "" }
$outFile = Join-Path $ScriptDir $OutDir "liboneapi.so"

Write-Output "Tags : '$Tags' $($tagArg ? "(no frontend)" : "(with frontend)")"
Write-Output "Output: $outFile"

$null = New-Item -ItemType Directory -Path (Split-Path $outFile -Parent) -Force
go build $tagArg -ldflags="-s -w" -o $outFile (Join-Path $GoSrc "main.go")
if ($LASTEXITCODE -ne 0) { throw "Go build failed" }

$size = (Get-Item $outFile).Length / 1MB
Write-Output "Binary size: $([math]::Round($size, 1)) MB"

if ($SkipGradle) {
    Write-Output "=== Done (APK skipped) ==="
    exit 0
}

# Stage 2 — Build APK via Gradle
Write-Output "=== Stage 2: Build APK ==="
$gradle = Join-Path $ScriptDir "gradlew.bat"
& $gradle assembleDebug --no-daemon
if ($LASTEXITCODE -ne 0) { throw "Gradle build failed" }

# Locate output APK
$apk = @(Get-ChildItem -Path (Join-Path $ScriptDir "app/build/outputs/apk") -Recurse -Filter "*.apk")[0]
if (-not $apk) { throw "No APK found after gradle build" }

Write-Output "=== Done ==="
Write-Output "APK : $($apk.FullName)  ($([math]::Round($apk.Length/1MB, 1)) MB)"
Write-Output "Tags: '$Tags'"
