# RM2100 NewAPI 交叉编译全记录

## 目标

将 NewAPI（AI API 网关）交叉编译并部署到 RM2100 路由器（MIPS 架构，126MB RAM），用本地 SQLite 跑压力测试。

## 环境

- **宿主机**: Windows 11, Go 1.25.1
- **交叉编译器**: musl.cc mipsel-linux-muslsf-cross (mipsel, soft-float, musl libc)
- **WSL**: Ubuntu 26.04（用于运行交叉编译器）
- **目标**: RM2100, MIPS 1004Kc, Padavan 固件 (glibc, kernel 3.4.113)
- **工具链大小**: 约 102MB

---

## 方法一：纯 Go + MySQL 远程（成功）

### 原理

NewAPI 源码原生支持 MySQL、PostgreSQL、SQLite 三种数据库，通过 `SQL_DSN` 环境变量切换。但 `github.com/glebarez/sqlite`（纯 Go SQLite 实现）依赖 `modernc.org/libc`，该包没有 mipsle build tag，导致 MIPS 交叉编译失败。

**核心思路：** 不修改任何源码，通过 `go.mod replace` 将 SQLite 包替换为自定义的空桩模块，彻底绕过 `modernc.org/libc` 的编译限制。运行时通过 `SQL_DSN=mysql://...` 连接远程 MySQL。

### 空桩模块（sqlite-stub）

在 `sqlite-stub/` 目录下创建一个只实现接口但不做任何实际工作的假包，导出同样的 `Open(dsn string) Dialector` 函数。`gorm.Open()` 调用 `Initialize()` 时返回错误，但编译时 `modernc.org/libc` 完全不会被引入。

### 步骤

```
1. 创建 sqlite-stub/ 目录
   - sqlite-stub/go.mod: module github.com/glebarez/sqlite
   - sqlite-stub/sqlite.go: 实现 gorm.Dialector 全接口（Name, Initialize, Migrator, DataTypeOf, DefaultValueOf, BindVarTo, QuoteTo, Explain）

2. go.mod 配置
   - 加一行: replace github.com/glebarez/sqlite => ./sqlite-stub

3. 编译（纯 Go，无 CGo）
   GOOS=linux GOARCH=mipsle GOMIPS=softfloat go build -tags no_web -ldflags="-s -w"

4. UPX 压缩
   upx --best --lzma → 55MB → 10MB

5. 部署
   scp 到路由器 /tmp/newapi（10MB，仅占 16% 的 61MB tmpfs）

6. 运行
   SQL_DSN='root:pass@tcp(host:3306)/newapi?charset=utf8mb4' /tmp/newapi --port 3000
```

### 数据库

MySQL 5.7 运行在 Windows Docker 容器中（Docker 已有现成的 `mybilibili-mysql` 容器），端口 3306 绑定到 `0.0.0.0`。Windows 通过 WiFi（192.168.123.159）连接路由器 LAN（192.168.123.1），MySQL 查询走 WiFi 链路。

### 二进制大小

| 格式 | 大小 |
|------|------|
| 未压缩 | 55MB |
| UPX --best --lzma | 10MB（压缩率 18%） |

### 测试结果

| 并发线程 | 吞吐 | 平均延迟 | 错误率 | CPU 使用 |
|---------|------|---------|-------|---------|
| 10t | 135/s | 57ms | 0% | <10% |
| 50t | 148/s | 250ms | 0% | <10% |
| 100t | 44/s | 1922ms | 40% | <10% |

### 问题：MySQL 网络开销污染压测数据

每次请求路由器都需要通过 WiFi 查询远程 MySQL，单次查询往返 200-400ms。后台同步任务（SyncOptions、SystemInstanceReporter、SubscriptionQuotaReset）也持续查询 MySQL，导致：

- 低并发（10t）：正常，但延迟偏高（57ms vs 本地 SQLite 的 36ms）
- 高并发（50t+）：MySQL 连接池被 200ms+ 的慢查询占满，请求排队超时
- CPU 使用率始终在 10% 以下，说明路由器根本没在干活

### 结论

纯 Go + MySQL 远程方案**可以运行**，但压测数据被网络延迟污染，**不能反映路由器真实处理能力**。仅适合功能验证，不适合性能基准测试。

---

## 方法二：CGo SQLite 本地（最终方案，成功）

### 原理

用 CGo 编译 `mattn/go-sqlite3`，SQLite 直接在路由器本地运行，零网络开销。

### 工具链获取

musl.cc 提供的 mipsel-linux-muslsf-cross 工具链（约 102MB）：

- WSL apt 源没有 mipsel gcc 包（Ubuntu 26.04 已移除 MIPS 支持）
- MSYS2 只有 mingw-w64-cross（目标 Windows，非 Linux/MIPS）
- LLVM clang 缺少 mipsle sysroot（找不到 stdlib.h）
- Clang + Android NDK：NDK 已移除 MIPS 支持
- Docker 无法拉取 dockcross 镜像（路由器网络无互联网）
- **最终方案**：用户开代理，Windows curl 下载 musl.cc 工具链（97MB，平均 752KB/s，用时 2分12秒）

### 编译

```
CGO_ENABLED=1 CC=mipsel-linux-muslsf-gcc \
GOOS=linux GOARCH=mipsle GOMIPS=softfloat \
go build -tags no_web -ldflags="-s -w -linkmode=external -extldflags=-static"
```

编译在 WSL 中完成，Go 1.25.1 临时安装到 WSL。

### 静态链接的必要性

musl 工具链默认生成动态链接二进制，需要 musl 的 ld-musl-mipsel-sf.so.1 作为 ELF 解释器。Padavan 固件只有 glibc，不存在 musl 解释器，所以直接运行动态链接二进制会报 `not found`。

解法：`-extldflags=-static` 将 musl libc 静态编入二进制，不依赖外部动态链接器。

### 错误记录

#### 错误 1: modernc.org/libc 不支持 mipsle

```
imports modernc.org/libc/errno: build constraints exclude all Go files
```

原因：`github.com/glebarez/go-sqlite`（纯 Go SQLite）依赖 `modernc.org/libc`，该包没有 mipsle build tag。

解决：改用 `gorm.io/driver/sqlite` → `mattn/go-sqlite3`（CGo 实现）。

#### 错误 2: CGo 编译缺少 stdlib.h

```
fatal error: 'stdlib.h' file not found
```

原因：Windows LLVM clang 没有 mipsle 的 Linux 系统头文件。

解决：安装 musl.cc 完整工具链（包含 sysroot）。

#### 错误 3: 动态链接二进制找不到解释器

```
sh: /opt/newapi: not found
```

原因：musl 编译的二进制需要 `/lib/ld-musl-mipsel-sf.so.1`，路由器没有。

尝试：拷贝 musl 的 libc.so 到路由器，运行 `/tmp/ld-musl-mipsel-sf.so.1 /opt/newapi` → Bus error（musl libc 与 kernel 3.4 不兼容）。

解决：`-extldflags=-static` 静态编译。

#### 错误 4: RWFS 分区 ext4 写入失败

```
mount: mounting /dev/mtdblock8 on /mnt failed: Device or resource busy
...
EXT4-fs (mtdblock8): previous I/O error to superblock detected
nand_erase_nand: attempt to erase a bad block
```

原因：SPI NOR flash + ext4 组合不可靠（mtdblock 驱动限制）。RWFS 分区有 I/O 错误。

解决：改用 /tmp（tmpfs，基于 RAM，稳定可靠）。

#### 错误 5: UPX 压缩版本 OOM

```
newapi invoked oom-killer
Killed process 23808 (newapi) total-vm:586520kB, anon-rss:65724kB
```

原因：UPX 解压时在匿名内存中创建 55MB 副本，额外增加内存压力。

解决：使用未压缩的二进制直接从 /tmp 运行（file-backed pages，更高效）。

#### 错误 6: 内存不足（OOM）

```
fatal error: runtime: out of memory
```

原因：55MB 二进制 + Go 运行时（20-30MB）+ SQLite + 系统进程 ≈ 接近 126MB 上限。

解决：/tmp 保持干净，SQLite 数据库文件放在 /tmp 共享空间。单次测试需重启清除状态。

### 最终二进制信息

| 项目 | 值 |
|------|-----|
| 编译器 | musl-gcc (mipsel-linux-muslsf-gcc) |
| 链接方式 | 静态链接 (-static) |
| 二进制大小 | 56MB |
| UPX 后大小 | 10.5MB |
| 启动时间 | ~1.1秒 |
| 运行内存 | ~60-80MB RSS |
| Go 版本 | 1.25.1 |

### 目标限制总结

| 限制 | 说明 |
|------|------|
| 126MB RAM | Go 二进制 55MB + 运行时 ≈ 上限，无法同时运行其他服务 |
| 880MHz MIPS | 峰值吞吐 ~150/s，CPU 瓶颈 |
| SPI NOR flash | ext4 不可靠，无法持久存储大型二进制 |
| kernel 3.4 | musl libc 动态链接不兼容，需静态编译 |
| 无 USB 端口 | 无法外接存储扩展空间 |

## 两种方法对比

| 项目 | 纯 Go + MySQL 远程 | CGo SQLite 本地 |
|------|-------------------|----------------|
| 编译方式 | 纯 Go，无 CGo | CGo，需要交叉编译器 |
| 工具链需求 | 无（Go 自带交叉编译） | musl/glibc mipsel gcc |
| 二进制大小 | 55MB（UPX 后 10MB） | 56MB（UPX 后 10.5MB） |
| 数据库位置 | Windows Docker（WiFi） | 路由器本地 |
| 网络开销 | 200-400ms/查询 | 0（本地） |
| 启动时间 | ~7秒（含迁移） | ~1.1秒 |
| 运行内存 | ~40MB（无 SQLite） | ~60-80MB |
| 10t 吞吐 | 135/s | 211/s |
| 20t 吞吐 | 不合适（WiFi 瓶颈） | 150/s |
| 30t 吞吐 | 不合适（WiFi 瓶颈） | 151/s |
| 可靠性 | 稳定，可长期运行 | 需预留 /tmp 空间，单次测试 |
| 适用场景 | 功能验证、长期部署 | 性能基准测试 |

## 关键教训

1. **静态编译是 MIPS CGo 开发的必要条件** — musl 工具链与 glibc 固件不兼容时，`-static` 解决一切
2. **UPX 压缩在低内存设备上可能适得其反** — 解压过程额外消耗内存
3. **/tmp (tmpfs) 是最可靠的临时存储** — SPI flash 的 ext4 写入不稳定
4. **压测前必须清理状态** — 残留的进程、数据库文件会影响后续测试准确性
5. **压测数据必须标注网络环境** — 远程数据库 vs 本地数据库的区别必须在报告中说明
6. **go.mod replace 是零侵入的跨平台兼容方案** — 不改一行源码，解决编译期依赖问题