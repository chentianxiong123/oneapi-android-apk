# OneAPI Android APK

在 Android 手机上运行 One API（AI API 中转站）的原生 APK 方案。

## 架构

```
MainActivity (原生配置界面) ─→ OneApiService (前台服务)
    │                                │
    │  SharedPrefs                   │ LD_PRELOAD libdns_hook.so
    │  端口 / DNS                    │ GODEBUG=netdns=go=1
    │                                │ 自定义 resolv.conf
    ▼                                ▼
WebViewActivity ◀── http://127.0.0.1:3000 ─── liboneapi.so (Go 二进制)
```

## 要求

| 项目 | 版本 |
|------|------|
| Android | 12+ (API 31), arm64-v8a |
| 存储 | APK ~35MB, 运行时 ~120MB |
| 内存 | ≥256MB |

## 快速开始

### 下载 APK

在 [Releases](../../releases) 页面下载最新 APK，手动安装到手机。

### 自行编译

需要: JDK 17+, Android SDK + NDK r27c, Go 1.24+, Node.js 20+

```powershell
# 一键编译
.\build.ps1

# 或手动步骤:
# 1. 克隆 one-api 源码
# 2. 编译前端 (npm install && npm run build)
# 3. NDK 交叉编译 Go 二进制
# 4. align_fix.py 修补 TLS alignment
# 5. 复制到 jniLibs
# 6. .\gradlew.bat assembleDebug
```

### 使用

1. 安装 APK，打开 "OneAPI Runner"
2. 配置端口（默认 3000）和 DNS（默认 8.8.8.8）
3. 点「启动」
4. 状态变「运行中」后点「管理后台」
5. 默认账号: `root` / `123456`
6. 局域网其他设备访问 `http://<手机IP>:3000`

## 关键技术

- **DNS 修复**: Android 子进程无法解析 DNS，通过 LD_PRELOAD 拦截 `/etc/resolv.conf` → 重定向到自定义文件
- **TLS 对齐**: ARM64 Bionic 要求 PT_TLS p_align=64，Go 交叉编译产物为 8，使用 `align_fix.py` 修补
- **PIE 要求**: Android 5.0+ 需要位置无关可执行文件，编译时加 `-buildmode=pie`
- **CGO SQLite**: go-sqlite3 需要 CGO，使用 NDK r27c 交叉编译

## 项目文件

| 路径 | 说明 |
|------|------|
| `app/.../MainActivity.java` | 原生配置界面 |
| `app/.../OneApiService.java` | 前台服务，管理二进制进程 |
| `app/.../WebViewActivity.java` | 管理后台 WebView |
| `app/.../cpp/dns_hook.c` | DNS 重定向 LD_PRELOAD 库 |
| `app/.../res/layout/` | XML 布局 |
| `align_fix.py` | TLS alignment 修补脚本 |
| `build.ps1` | 全自动编译脚本 |

## License

MIT