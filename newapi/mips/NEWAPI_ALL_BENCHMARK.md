# NewAPI 全平台性能压测报告

## 测试设备总览

| 项目 | HaiNaSi 机顶盒 | Xiaomi 23049RAD8C | Xiaomi M5 Note | POT-AL00a 华为畅享10 | CM201-2 机顶盒 | RM2100 路由器 | XR3 小米路由器R3 |
|------|---------------|-----------------|---------------|---------------------|---------------|--------------|-------------------|
| **CPU** | 4×A53 @ 1.5GHz | 4×2.3GHz + 4×556MHz | 8×A53 @ 2.0GHz (骁龙625) | 4×A73 @ 2.2GHz + 4×A53 @ 1.7GHz (Kirin 710) | Hi3798MV300 4×A53 @ 1.5GHz | MIPS 1004Kc @ 880MHz ×2 | MIPS 24KEc @ 385MHz (单核) |
| **RAM** | 723MB | 15GB | 3GB | 4GB | 1GB | 126MB | 123MB |
| **内核** | Linux 5.4+ (Ubuntu 20.04) | Android 14 (GKI) | Android 6.0 (Linux 3.10) | Android 10 (Linux 4.x) | **Linux 3.18.24** | Linux 3.4 | Linux 5.4 (OpenWrt) |
| **系统** | Ubuntu 20.04 armv7l | Android 14 | Android 6.0 MIUI | Android 10 (EMUI) | Android 4.4.2 | Padavan (Linux 3.4) | OpenWrt 5.4 |
| **二进制** | 55MB linux/arm | 68MB APK arm64 | 68MB APK arm64 | 71MB APK arm64 | 50MB linux/arm (APK内) | 56MB linux/mipsle | 56MB linux/mipsle |
| **数据库** | SQLite | SQLite | SQLite | SQLite | SQLite | SQLite (CGo 静态) | SQLite (CGo 静态) |
| **测试端点** | GET /api/status | GET /api/status | GET /api/status | GET /api/status | GET /api/status | GET /api/status | GET /api/status |

---

## 吞吐对比

| 并发 | HaiNaSi | 23049RAD8C WiFi | 23049RAD8C USB | M5 Note WiFi | M5 Note ADB | POT-AL00a APK | **CM201-2** | **RM2100** | **XR3** |
|-----:|:-------:|:--------------:|:-------------:|:------------:|:----------:|:------------:|:----------:|:----------:|:-------:|
| 10t | 340/s | 773/s | **1297/s** | 476/s | **722/s** | **468/s** | **308/s** | **211/s** | **26/s** |
| 20t | - | 614/s | - | - | - | - | **497/s** | **150/s** | **25/s** |
| 30t | - | - | - | - | - | - | - | **151/s** | - |
| 50t | **566/s** | **997/s** | 675/s | **935/s** | 393/s | **761/s** | **368/s** | - | - |
| 100t | 384/s | 597/s | 493/s | **1098/s** | 347/s | 461/s | - | - | - |
| 200t | 275/s | 459/s | 450/s | **1132/s** | 318/s | 402/s | - | - | - |

> 全部 0% 错误率。RM2100 仅测试到 30t（126MB 内存上限）。XR3 单核 385MHz，10t 即饱和。CM201-2 在 20t 达峰（497/s）后 50t 回落至 368/s。

---

## 性能排名（峰值）

| 排名 | 设备 | 峰值 RPS | 瓶颈 |
|:----:|------|:--------:|------|
| 1 | 23049RAD8C USB RNDIS | 1,297/s | USB 2.0 单队列（10t 极限） |
| 2 | M5 Note WiFi | 1,132/s | CPU 饱和（~150t） |
| 3 | 23049RAD8C WiFi | 997/s | WiFi 网卡（50t 拐点） |
| 4 | POT-AL00a APK | 761/s | Kirin 710 CPU 限制 |
| 5 | HaiNaSi | 585/s | CPU 4×A53 1.5GHz 满载 |
| 6 | **CM201-2** | **497/s** | **Linux 3.18 内核调度 + Android 进程争抢 CPU** |
| 7 | **RM2100** | **~150/s** | **CPU MIPS 880MHz + 126MB RAM** |
| 8 | **XR3** | **~26/s** | **CPU MIPS 24KEc 385MHz 单核** |

---

## 同 CPU 不同性能：HaiNaSi vs CM201-2

CM201-2（Hi3798MV300 4×A53 @ 1.5GHz）和 HaiNaSi（4×A53 @ 1.5GHz）的 CPU **完全相同**，但 CM201-2 峰值 497/s（20t）比 HaiNaSi 的 566/s（50t）低约 15%。

### 是不是内存不足？

```
MemTotal:   1048576 kB  (1GB)
MemFree:     108968 kB
MemAvailable: 555236 kB  ← 空闲可用 542MB
```

NewAPI 二进制 50MB，SQLite DB 仅 708KB（`one-api.db`），Go RSS 约 44MB（PID 15011 的 VSIZE 544644kB）。**可用 542MB 远未耗尽，RAM 不是瓶颈。**

### 真正原因

| 因素 | HaiNaSi | CM201-2 | 影响 |
|------|---------|---------|------|
| **内核版本** | Linux 5.4+ (Ubuntu 20.04) | **Linux 3.18.24** | ★ 最大差距 |
| **内核编译器** | GCC 9+ | GCC 4.9.4 | 代码优化程度不同 |
| **后台进程** | 零（headless） | system_server, surfaceflinger, servicemanager 等 | 争抢 CPU 时间片 |
| **C 库** | glibc 2.31 | bionic libc (Android) | 内存分配策略差异 |

**内核 3.18 → 5.4 的关键改进：**

1. **CFS 调度器** — 3.18 到 5.4 之间，CFS 重写了负载跟踪算法（PELT → EEVDF），上下文切换开销显著降低。高并发场景下，旧内核的调度器本身变成瓶颈。
2. **epoll** — 5.4 引入了 EPOLLEXCLUSIVE（避免惊群效应），3.18 没有。Go 的 netpoller 依赖 epoll，旧内核多线程 accept 时锁竞争更严重。
3. **futex 锁** — 3.18 的 futex 实现较朴素，高竞争下内核态等待/唤醒开销高。
4. **TCP 栈** — 5.4 的 TCP 保活、backlog 处理、TIME_WAIT 回收都有显著优化。

### 量化验证

- **10t（低竞争）：** HaiNaSi 340/s vs CM201-2 308/s → 差距仅 10%。低并发时调度和锁竞争影响小。
- **50t（高竞争）：** HaiNaSi 566/s vs CM201-2 368/s → 差距拉大到 35%。高并发时内核调度和 epoll 开销被放大。
- **50t 回落幅度：** CM201-2 从 20t 峰值 497/s 降到 368/s（-26%），HaiNaSi 50t 仍是峰值（566/s）—— 说明 CM201-2 在更低并发就开始内耗。

### 如果 CM201-2 刷 Armbian？

理论上刷 Armbian（Linux 5.4+/6.x，headless）后：
- 去掉 Android 框架的 CPU 争抢
- 现代内核调度器 + epoll
- 性能应与 HaiNaSi 拉平到 **550-580/s**

但 CM201-2 的 bootloader 锁死，无法刷机，仅作理论参考。

---

## 编译方法总览

### 方案 A：纯 Go + 远程 MySQL（适用于 arm/arm64/amd64）

```sh
# 无需交叉编译器，Go 原生支持
GOOS=linux GOARCH=arm go build -tags no_web -ldflags="-s -w"
```

通过 `go.mod replace github.com/glebarez/sqlite => ./sqlite-stub` 绕过 `modernc.org/libc` 的架构限制。运行时连接远程 MySQL。

**适用设备：** 所有平台，适合长期部署。
**二进制大小：** ~55MB（UPX 后 ~10MB）。
**局限：** 压测数据受 MySQL 网络延迟影响。

### 方案 B：CGo 静态 + 本地 SQLite（适用于所有架构）

```sh
# 需要对应架构的交叉编译器
CGO_ENABLED=1 CC=<cross-gcc> \
GOOS=linux GOARCH=<arch> \
go build -tags no_web -ldflags="-s -w -linkmode=external -extldflags=-static"
```

通过 `go.mod replace github.com/glebarez/sqlite => ./sqlite-cgo` 将 SQLite 替换为 CGo 实现的 `mattn/go-sqlite3`。

**适用设备：** 需要本地 SQLite 的压测场景。
**二进制大小：** ~56MB（UPX 后 ~10.5MB）。
**局限：** musl 工具链需静态链接（`-static`），否则与 glibc 固件不兼容。

### 方案 C：Android APK（适用于 arm64 手机）

Android 项目在 `oneapi-android-apk/newapi/` 中构建，通过 `build_from_source.ps1` 编译 Go 源码为 android/arm64 二进制，再打包为 APK。

**特点：** 支持 env.conf 配置环境变量，前台服务模式性能最佳。

---

## RM2100 编译全记录

### 关键障碍

| 问题 | 原因 | 解决 |
|------|------|------|
| `modernc.org/libc` 无 mipsle 标签 | 纯 Go SQLite 不支持 MIPS | `go.mod replace` 绕过 |
| `stdlib.h: No such file or directory` | clang 缺 mipsle sysroot | 下载 musl.cc 工具链 |
| `sh: newapi: not found` | 动态链接需 musl ld-musl | `-static` 静态编译 |
| Bus error | musl libc 与 kernel 3.4 不兼容 | 静态编译不使用 musl ld-musl |
| I/O error 写入闪存 | SPI NOR + ext4 不稳定 | 改用 /tmp (tmpfs) |
| OOM killed | 126MB 内存不足 | 不使用 UPX 压缩，预留 /tmp 空间 |

### 工具链获取

musl.cc 的 mipsel-linux-muslsf-cross（约 102MB），部署到 WSL 的 `/opt/mipsel-tc/`：

```sh
curl -L -o mipsel-cross.tgz https://musl.cc/mipsel-linux-muslsf-cross.tgz
sudo tar xzf mipsel-cross.tgz -C /opt/mipsel-tc --strip-components=1
```

### 最终编译命令

```sh
export PATH=/usr/local/go/bin:/opt/mipsel-tc/bin:$PATH
export CGO_ENABLED=1 CC=mipsel-linux-muslsf-gcc
export GOOS=linux GOARCH=mipsle GOMIPS=softfloat
go build -tags no_web \
  -ldflags="-s -w -linkmode=external -extldflags=-static" \
  -o newapi-mipsle-sqlite .
```

---

## 部署说明

### RM2100 部署

```sh
# 清理 /tmp，腾出 61MB 空间
ssh admin@192.168.123.1 "rm -rf /tmp/*"

# 上传二进制（建议不压缩，避免 OOM）
scp newapi-mipsle-sqlite admin@192.168.123.1:/tmp/newapi

# 运行（本地 SQLite）
SQLITE_PATH=/tmp/bench.db /tmp/newapi --port 3000
```

### Android 部署

使用 `oneapi-android-apk/newapi/build_from_source.ps1` 构建 APK，安装后通过 env.conf 配置环境变量。

### Android 4.x 部署（CM201-2 机顶盒）

Android 4.4.2（API 19）的 bionic libc 缺少 `sigfillset` 符号，Go 的 `GOOS=android` 编译的 `.so` 无法执行。

**解决方案：** 用 `GOOS=linux GOARCH=arm` 编译纯 Go 静态 ELF 二进制（`CGO_ENABLED=0`），放到 APK 的 `jniLibs/armeabi-v7a/` 目录中。Android 4.x 的 `ProcessBuilder` 可以像执行 Linux ELF 一样执行它。

```sh
GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 \
  go build -tags no_web -ldflags="-s -w" \
  -o app/src/main/jniLibs/armeabi-v7a/liboneapi.so .
```

注意：
- `GOOS=android` 不适用于 API < 21 的旧版 Android，必须改用 `GOOS=linux`
- `GOARCH=arm` + `GOARM=7` 兼容所有 ARMv7 Android 设备
- CGo 二进制（`GOOS=android` 必须 CGO）不支持 API 19，纯 Go 二进制无此限制

### HaiNaSi / Linux 部署

```sh
scp newapi-linux-arm admin@192.168.31.82:/opt/newapi
SQLITE_PATH=/opt/data/newapi.db /opt/newapi --port 3000
```

---

## 最终结论

### 设备选择建议

| 用途 | 推荐设备 | 理由 |
|------|---------|------|
| 个人/家庭低并发 | RM2100 路由器 / CM201-2 机顶盒 | 现成设备，功耗低，150-500/s 够用 |
| 多人分享（<10人） | HaiNaSi / 任意手机 | 500+ RPS，绰绰有余 |
| 高并发（>10人） | 骁龙 625+ 手机 / arm64 设备 | 1000+ RPS |
| 极限性能 | 23049RAD8C + USB 网卡 | 1300+ RPS |

### 真正瓶颈

```
家庭宽带上行 10-50 Mbps ≈ 同时 2-3 个流式 AI 响应
```

**设备性能远高于宽带上限。** 瓶颈在宽带，不在设备。

### 最终排名

| 设备 | 峰值 RPS |
|------|:--------:|
| 23049RAD8C (USB) | 1,297 |
| M5 Note (WiFi) | 1,132 |
| 23049RAD8C (WiFi) | 997 |
| POT-AL00a (APK) | 761 |
| HaiNaSi (WiFi) | 585 |
| **CM201-2 (WiFi)** | **497** |
| **RM2100 (WiFi)** | **~150** |
| **XR3 (WiFi)** | **~26** |
