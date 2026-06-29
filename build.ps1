param(
    [string]$OneApiRepo = "https://github.com/songquanpeng/one-api.git",
    [string]$OneApiDir = "$PSScriptRoot\one-api-src",
    [string]$NDKPath = "",
    [string]$ApiLevel = "31"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot

# ─── Prerequisites ──────────────────────────────────────────────────
function Check-Requirements {
    $ok = $true
    if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
        Write-Warning "Java not found. Install JDK 17+ and set JAVA_HOME."
        $ok = $false
    }
    if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
        Write-Warning "Go not found. Install Go 1.21+."
        $ok = $false
    }
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Warning "Node.js not found."
        $ok = $false
    }
    if (-not $env:ANDROID_HOME -and -not (Test-Path "$env:ANDROID_HOME")) {
        Write-Warning "ANDROID_HOME not set or invalid."
        $ok = $false
    }
    if (-not $NDKPath) {
        $NDKPath = "$env:ANDROID_HOME\ndk\27.0.12077973"
    }
    if (-not (Test-Path "$NDKPath\toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android${ApiLevel}-clang.cmd")) {
        Write-Warning "NDK not found at $NDKPath (API $ApiLevel)."
        $ok = $false
    }
    if (-not $ok) { exit 1 }
    return $NDKPath
}

# ─── Step 1: Clone / update one-api source ──────────────────────────
function Step-CloneOneApi {
    Write-Host "=== [1/6] Clone/update One API source ==="
    if (Test-Path $OneApiDir) {
        Set-Location $OneApiDir
        git pull
    } else {
        git clone --depth 1 $OneApiRepo $OneApiDir
        Set-Location $OneApiDir
    }
}

# ─── Step 2: Build web frontend ──────────────────────────────────────
function Step-BuildFrontend {
    Write-Host "=== [2/6] Build web frontend ==="
    Set-Location "$OneApiDir\web\default"
    npm install
    $env:DISABLE_ESLINT_PLUGIN = "true"
    npm run build
    if (Test-Path "build") {
        if (Test-Path "$OneApiDir\web\build\default") { Remove-Item -Recurse -Force "$OneApiDir\web\build\default" }
        Move-Item -Force "build" "$OneApiDir\web\build\default"
    }
}

# ─── Step 3: Cross-compile Go binary ─────────────────────────────────
function Step-CompileGo {
    Write-Host "=== [3/6] Cross-compile Go binary ==="
    Set-Location $OneApiDir
    $cc = "$NDKPath\toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android${ApiLevel}-clang.cmd"
    $env:CC = $cc
    $env:CGO_ENABLED = "1"
    $env:GOOS = "android"
    $env:GOARCH = "arm64"
    go build -tags 'osusergo' -buildmode=pie `
        -ldflags '-s -w -extldflags "-Wl,-z,max-page-size=4096"' `
        -o "$ProjectRoot\one-api-android"
    Write-Host "Binary: $((Get-Item "$ProjectRoot\one-api-android").Length / 1MB) MB"
}

# ─── Step 4: Patch TLS alignment ────────────────────────────────────
function Step-PatchTls {
    Write-Host "=== [4/6] Patch TLS alignment ==="
    Set-Location $ProjectRoot
    python align_fix.py one-api-android
}

# ─── Step 5: Download tiktoken cache ─────────────────────────────────
function Step-DownloadTiktoken {
    Write-Host "=== [5/7] Download tiktoken cache ==="
    $assetsDir = "$ProjectRoot\app\src\main\assets"
    $tokenFile = "$assetsDir\cl100k_base.tiktoken"
    if (-not (Test-Path $tokenFile)) {
        if (-not (Test-Path $assetsDir)) { New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null }
        Invoke-WebRequest -Uri "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken" -OutFile $tokenFile -UseBasicParsing
        Write-Host "Downloaded tiktoken cache"
    } else {
        Write-Host "Already exists, skipping"
    }
}

# ─── Step 6: Copy to jniLibs ────────────────────────────────────────
function Step-CopyBinary {
    Write-Host "=== [6/7] Copy to jniLibs ==="
    $targetDir = "$ProjectRoot\app\src\main\jniLibs\arm64-v8a"
    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
    Copy-Item "$ProjectRoot\one-api-android" "$targetDir\liboneapi.so" -Force
}

# ─── Step 7: Build APK ──────────────────────────────────────────────
function Step-BuildApk {
    Write-Host "=== [7/7] Build APK ==="
    Set-Location $ProjectRoot
    .\gradlew.bat assembleDebug
    Copy-Item "app\build\outputs\apk\debug\app-debug.apk" "OneAPI.apk" -Force
    Write-Host "Done! APK: $((Get-Item 'OneAPI.apk').Length / 1MB) MB"
}

# ─── Main ────────────────────────────────────────────────────────────
$NDKPath = Check-Requirements
Write-Host "NDK: $NDKPath"
Write-Host ""

Step-CloneOneApi
Step-BuildFrontend
Step-CompileGo
Step-PatchTls
Step-DownloadTiktoken
Step-CopyBinary
Step-BuildApk

Write-Host ""
Write-Host "✅ APK ready: $ProjectRoot\OneAPI.apk"