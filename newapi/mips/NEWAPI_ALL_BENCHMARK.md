# NewAPI 全平台性能压测报告

## 测试设备总览

| 项目 | HaiNaSi 机顶盒 | Xiaomi 23049RAD8C | Xiaomi M5 Note | Huawei RIO-UL00 | RM2100 路由器 |
|------|---------------|-----------------|---------------|-----------------|--------------|
| **CPU** | 4×A53 @ 1.5GHz | 4×2.3GHz + 4×556MHz | 8×A53 @ 2.0GHz (骁龙625) | 4×1.5GHz + 4×1.2GHz (骁龙616) | MIPS 1004Kc @ 880MHz ×2 |
| **RAM** | 723MB | 15GB | 3GB | 2GB | 126MB |
| **系统** | Ubuntu 20.04 armv7l | Android 14 | Android 6.0 MIUI | Android 6.0.1 EMUI | Padavan (Linux 3.4) |
| **二进制** | 55MB linux/arm | 68MB APK arm64 | 68MB APK arm64 | 68MB APK / 55MB 纯二进制 | 56MB linux/mipsle |
| **数据库** | SQLite | SQLite | SQLite | SQLite | SQLite (CGo 静态) |
| **测试端点** | GET /api/status | GET /api/status | GET /api/status | GET /api/status | GET /api/status |

---

## 吞吐对比

| 并发 | HaiNaSi | 23049RAD8C WiFi | 23049RAD8C USB | M5 Note WiFi | M5 Note ADB | Huawei APK | Huawei 纯二进制 | **RM2100 SQLite** |
|-----:|:-------:|:--------------:|:-------------:|:------------:|:----------:|:----------:|:--------------:|:----------------:|
| 10t | 340/s | 773/s | **1297/s** | 476/s | **722/s** | 300/s | 255/s | **211/s** |
| 20t | - | 614/s | - | - | - | - | - | **150/s** |
| 30t | - | - | - | - | - | - | - | **151/s** |
| 50t | **566/s** | **997/s** | 675/s | **935/s** | 393/s | **637/s** | 471/s | - |
| 100t | 384/s | 597/s | 493/s | **1098/s** | 347/s | 618/s | 553/s | - |
| 200t | 275/s | 459/s | 450/s | **1132/s** | 318/s | 576/s | 527/s | - |

> 全部 0% 错误率。RM2100 仅测试到 30t（126MB 内存上限）。

---

## 性能排名（峰值）

| 排名 | 设备 | 峰值 RPS | 瓶颈 |
|:----:|------|:--------:|------|
| 1 | 23049RAD8C USB RNDIS | 1,297/s | USB 2.0 单队列（10t 极限） |
| 2 | M5 Note WiFi | 1,132/s | CPU 饱和（~150t） |
| 3 | 23049RAD8C WiFi | 997/s | WiFi 网卡（50t 拐点） |
| 4 | Huawei APK 亮屏 | 637/s | CPU big.LITTLE 限制 |
| 5 | HaiNaSi | 585/s | CPU 4×A53 1.5GHz 满载 |
| 6 | **RM2100** | **~150/s** | **CPU MIPS 880MHz + 126MB RAM** |

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
| 个人/家庭低并发 | RM2100 路由器 | 现成设备，功耗低，150/s 够用 |
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
| Huawei (APK 亮屏) | 637 |
| HaiNaSi (有线) | 585 |
| **RM2100 (SQLite)** | **~150** |
