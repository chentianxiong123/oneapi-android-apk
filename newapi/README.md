# New API Android APK

Run [New API](https://github.com/QuantumNous/new-api) v1.0.0-rc.15 on Android — no Termux needed.

## Build

```bash
# 1. Download the arm64 binary
cd newapi
pwsh download-binary.ps1

# 2. Build APK (Go >= 1.25, no align_fix needed)
./gradlew assembleDebug
```

APK at `app/build/outputs/apk/debug/app-debug.apk`.

## Download

Grab the latest APK from [Releases](https://github.com/chentianxiong123/oneapi-android-apk/releases).

## Usage

1. Install the APK
2. Open **NewAPI Runner**
3. Set port (default 3000) and DNS (default 8.8.8.8,8.8.4.4)
4. Tap **启动**
5. Tap **管理后台** to open the admin UI

Default login: `root` / `123456`

## How It Works

| Component | Role |
|-----------|------|
| `liboneapi.so` | New API Go binary (CGO_ENABLED=0, linux/arm64) |
| `libdns_hook.so` | LD_PRELOAD hook — redirects `/etc/resolv.conf` |
| `OneApiService.java` | Process lifecycle + env vars |
| `MainActivity.java` | Config UI (port, DNS) |
| `WebViewActivity.java` | Admin SPA viewer |

DNS: `LD_PRELOAD=libdns_hook.so` + `GODEBUG=netdns=go=1`