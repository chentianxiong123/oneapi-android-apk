# MIPS (mipsel/mipsle) 交叉编译指南

## 版本分类

| 版本 | 数据库 | 前端 | 内存 | 编译方式 | 用途 |
|------|--------|------|------|---------|------|
| **mysql** | 远程 MySQL | 无 | ~40MB | 纯 Go 交叉编译 | 长期部署 |
| **mysql-upx** | 远程 MySQL | 无 | ~40MB | 纯 Go 交叉编译 + UPX | 长期部署（省空间） |
| **mysql-web** | 远程 MySQL | 有 | ~100MB | 纯 Go 交叉编译 | 参考（126MB 设备跑不了） |
| **sqlite** | 本地 SQLite | 无 | ~60-80MB | CGo 静态交叉编译 | 性能压测 |
| **sqlite-upx** | 本地 SQLite | 无 | ~60-80MB | CGo 静态交叉编译 + UPX | 压测（低内存设备慎用） |

## 最终产物

`bin/release/` 目录下：

| 文件 | 类型 | 大小 | 说明 |
|------|------|------|------|
| `newapi-mipsle-mysql` | 纯 Go | 55MB | 远程 MySQL 版（UPX 后 10MB） |
| `newapi-mipsle-mysql-upx` | 纯 Go UPX | 10MB | 远程 MySQL 版 UPX 压缩 |
| `newapi-mipsle-mysql-web` | 纯 Go | 130MB | 远程 MySQL + 前端（参考用） |
| `newapi-mipsle-sqlite` | CGo 静态 | 56MB | 本地 SQLite 版（UPX 后 10.5MB） |
| `newapi-mipsle-sqlite-upx` | CGo 静态 UPX | 10.5MB | 本地 SQLite 版 UPX 压缩 |

## 一键编译

使用 `build-all.ps1`：

```powershell
.\build-all.ps1                    # 编译全部版本
.\build-all.ps1 -OnlyMySQL -NoWeb  # 仅编译 MySQL 无前端版
.\build-all.ps1 -OnlySQLite        # 仅编译 SQLite 版（需要 WSL + musl 工具链）
```

---

## 方案 A：纯 Go + MySQL 远程

### 适用场景

- 路由器有网络连接远程 MySQL/PostgreSQL
- 不希望使用 CGo 交叉编译器
- 长期稳定部署（内存占用更低）

### 原理

通过 `go.mod replace` 将 SQLite 替换为空桩模块，绕过 `modernc.org/libc` 的编译限制。

### 前置条件

- Go 1.22+（宿主机）
- 无额外工具链需求（Go 自带 mipsle 交叉编译）

### 编译

```sh
# 设置 go.mod replace
go mod edit -replace github.com/glebarez/sqlite=./sqlite-stub

# 交叉编译（无前端）
GOOS=linux GOARCH=mipsle GOMIPS=softfloat \
  go build -tags no_web -ldflags="-s -w" \
  -o bin/release/newapi-mipsle-mysql .

# 交叉编译（有前端，130MB，RM2100 跑不了）
GOOS=linux GOARCH=mipsle GOMIPS=softfloat \
  go build -ldflags="-s -w" \
  -o bin/release/newapi-mipsle-mysql-web .
```

### 部署

```sh
# 可选：UPX 压缩
upx --best --lzma -o bin/release/newapi-mipsle-mysql-upx bin/release/newapi-mipsle-mysql

# 上传到路由器
scp bin/release/newapi-mipsle-mysql-upx admin@192.168.123.1:/tmp/newapi

# 运行
SQL_DSN='root:password@tcp(mysql_host:3306)/newapi?charset=utf8mb4&parseTime=True' \
  /tmp/newapi --port 3000
```

### 注意事项

- MySQL 查询延迟会污染压测数据（WiFi 下 200-400ms/查询）
- 高压并发时 MySQL 连接池可能堵塞
- 压测结果需标注"远程 MySQL 环境"

---

## 方案 B：CGo 静态 + 本地 SQLite

### 适用场景

- 需要本地 SQLite 进行性能基准测试
- 离线环境或无数据库服务器
- 单次测试场景（非长期部署）

### 前置条件

- Go 1.22+（宿主机或 WSL）
- mipsel 交叉编译器（musl.cc 工具链）
- WSL 或 Linux 环境（运行交叉编译器）

### 工具链获取

```sh
# musl.cc 提供的 mipsel 工具链（约 102MB）
curl -L -o mipsel-cross.tgz https://musl.cc/mipsel-linux-muslsf-cross.tgz
sudo tar xzf mipsel-cross.tgz -C /opt/mipsel-tc --strip-components=1
```

其他尝试过的选项（均不可行）：
- WSL apt：Ubuntu 26.04 无 `gcc-mipsel-linux-gnu` 包
- MSYS2：只有 mingw-w64-cross（目标 Windows）
- LLVM clang：缺少 mipsle sysroot
- Docker：路由器无互联网，无法拉取 dockcross 镜像

### CGo 适配层

创建 `sqlite-cgo/` 目录，包装 `gorm.io/driver/sqlite`：

```go
package sqlite

import (
    gormSqlite "gorm.io/driver/sqlite"
    "gorm.io/gorm"
    "gorm.io/gorm/clause"
    "gorm.io/gorm/schema"
)

type Dialector struct {
    inner gorm.Dialector
}

func Open(dsn string) Dialector {
    return Dialector{inner: gormSqlite.Open(dsn)}
}
// ... 其余接口方法委派给 inner
```

### 编译

```sh
# 设置 go.mod replace
go mod edit -replace github.com/glebarez/sqlite=./sqlite-cgo

# 静态交叉编译（必须 -static！）
CGO_ENABLED=1 CC=mipsel-linux-muslsf-gcc \
GOOS=linux GOARCH=mipsle GOMIPS=softfloat \
go build -tags no_web \
  -ldflags="-s -w -linkmode=external -extldflags=-static" \
  -o bin/release/newapi-mipsle-sqlite .
```

### 部署

```sh
# 清理路由器 /tmp（腾出 61MB 空间）
ssh admin@192.168.123.1 "rm -rf /tmp/*"

# 上传（建议不压缩，避免 UPX 解压额外内存开销）
scp bin/release/newapi-mipsle-sqlite admin@192.168.123.1:/tmp/newapi

# 运行
SQLITE_PATH=/tmp/bench.db /tmp/newapi --port 3000
```

### 注意事项

- 必须静态链接（`-static`），否则 musl libc 与 Padavan glibc 不兼容
- 二进制 56MB 占 /tmp 的 90%，剩余空间仅约 6MB
- UPX 压缩版本在 126MB 内存设备上可能 OOM（解压额外消耗内存）
- 每轮测试前必须重启进程并清理 /tmp，避免状态残留

---

## 故障排除

| 错误 | 原因 | 解决 |
|------|------|------|
| `build constraints exclude all Go files` | `modernc.org/libc` 无 mipsle 标签 | 用 `go mod replace` 绕过或改用 CGo |
| `stdlib.h: No such file or directory` | 缺少交叉编译 sysroot | 安装完整工具链 |
| `sh: /path/newapi: not found` | ELF 动态链接器不存在 | 静态编译（`-static`） |
| `Bus error` | musl libc 与 kernel 3.4 不兼容 | 静态编译，不使用 musl ld-musl |
| `Input/output error` 写入闪存 | SPI NOR + ext4 不稳定 | 改用 /tmp（tmpfs） |
| `OOM killed` | 内存不足 | 不压缩运行，预留 /tmp 空间 |
| `HTTP 429/高错误率` 压测 | 限流或状态残留 | 重启进程，清理数据库 |
