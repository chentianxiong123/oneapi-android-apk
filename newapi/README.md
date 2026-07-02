# New API Android APK

Run [New API](https://github.com/QuantumNous/new-api) v1.0.0-rc.15 on Android — no Termux needed.

## Build

```bash
# 1. Build Go .so (arm64 or armeabi-v7a)
cd newapi
pwsh build_from_source.ps1 -Tags no_web          # arm64 only
pwsh build_from_source.ps1 -Tags no_web -GOARCH arm -OutDir armeabi-v7a   # 32-bit ARM
# Or: place pre-built .so in app/src/main/jniLibs/{arm64-v8a,armeabi-v7a}/

# 2. Build APK
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

## Android 4.x Support

The APK targets **minSdk 16** (Android 4.1 Jelly Bean). Changes made:

| File | Change | Why |
|------|--------|-----|
| `app/build.gradle` | `minSdk 21` → `minSdk 16` | Allow install on Android 4.1+ |
| `AndroidManifest.xml` | Removed `FOREGROUND_SERVICE` permission (API 28+) | Not available on older Android |
| `AndroidManifest.xml` | Removed `POST_NOTIFICATIONS` permission (API 33+) | Not available on older Android |
| `AndroidManifest.xml` | Removed `foregroundServiceType="dataSync"` (API 29+) | Not available on older Android |
| `gradle.properties` | Added `suppressMinSdkVersionError` | NDK C++ requires API 21, but the hook lib is optional |

Go's `android/arm` target requires minimum **API 16**; pure Go 4.0 (API 14) is not supported.

### Android 4.4 (API 19) Known Issue

`GOOS=android` compiled binaries fail on Android 4.4.2 with `cannot locate symbol "sigfillset"` — the old bionic libc doesn't export this symbol.

**Workaround:** Build with `GOOS=linux GOARCH=arm` instead of `GOOS=android`. The resulting static ELF binary (CGO_ENABLED=0) runs correctly on Android 4.x through ProcessBuilder:

```sh
GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 \
  go build -tags no_web -ldflags="-s -w" \
  -o app/src/main/jniLibs/armeabi-v7a/liboneapi.so .
```

## How It Works

| Component | Role |
|-----------|------|
| `liboneapi.so` | New API Go binary (CGO_ENABLED=0, android/arm64 or android/arm) |
| `libdns_hook.so` | LD_PRELOAD hook — redirects `/etc/resolv.conf` |
| `OneApiService.java` | Process lifecycle + env vars |
| `MainActivity.java` | Config UI (port, DNS) |
| `WebViewActivity.java` | Admin SPA viewer |

DNS: `LD_PRELOAD=libdns_hook.so` + `GODEBUG=netdns=go=1`