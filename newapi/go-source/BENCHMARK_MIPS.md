# RM2100 路由器 NewAPI 压测报告

## 设备信息

| 项目 | 值 |
|------|-----|
| 型号 | RM2100 (红米 AC2100) |
| SoC | MT7621A MIPS 1004Kc |
| CPU | 双核 880MHz |
| RAM | 126MB |
| 固件 | Padavan 3.4.3.9-099_23-07-1 (hiboy) |
| Linux 内核 | 3.4.113 |
| 网络 | 1000M LAN（有线测试） |
| 测试工具 | JMeter 5.6.3 |
| 测试 endpoint | GET /api/status |

## 最终方案

**CGo 静态编译 + 本地 SQLite**

- Go 交叉编译：mipsel (mipsle softfloat)
- CGo SQLite：`mattn/go-sqlite3` via `gorm.io/driver/sqlite`
- 工具链：musl.cc mipsel-linux-muslsf-cross
- 构建参数：`CGO_ENABLED=1 CC=mipsel-linux-muslsf-gcc GOOS=linux GOARCH=mipsle GOMIPS=softfloat go build -tags no_web -ldflags="-s -w -linkmode=external -extldflags=-static"`
- 存储方式：不压缩，二进制放 /tmp (61MB tmpfs)
- 数据库：SQLite 本地，路径 /tmp/bench.db
- 压测链路：JMeter → 有线 → RM2100:3000 → 本地 SQLite（零网络开销）

## 基准测试结果

| 并发线程 | 总请求数 | 吞吐 (req/s) | 平均延迟 | 最小延迟 | 最大延迟 | 错误率 |
|---------|---------|-------------|---------|---------|---------|-------|
| 10t | 4,238 | **211/s** | 36ms | 7ms | 2,679ms | 0% |
| 20t | 3,200 | **150/s** | 96ms | 10ms | 4,207ms | 0% |
| 30t | 3,461 | **151/s** | 138ms | 9ms | 8,934ms | 0% |

- **峰值吞吐：~150 req/s**
- **瓶颈：CPU（MIPS 880MHz 双核满载）**
- **内存峰值：约 112MB / 126MB（二进制 55MB + Go 运行时 + SQLite）**

## 对比：远程 MySQL 方案

使用纯 Go + sqlite-stub + 远程 MySQL 时，压测数据被网络延迟污染：

| 并发线程 | 吞吐 | 平均延迟 | 错误率 | CPU 使用 |
|---------|------|---------|-------|---------|
| 10t | 135/s | 57ms | 0% | <10% |
| 50t | 148/s | 250ms | 0% | <10% |
| 100t | 44/s | 1922ms | 40% | <10% |

MySQL 查询走 WiFi 往返 200-400ms，连接池堵塞导致高并发时大量超时。

## 与其他设备对比

| 设备 | CPU | RAM | 峰值吞吐 | 瓶颈 |
|------|-----|-----|---------|------|
| **RM2100** | MIPS 880MHz ×2 | 126MB | **~150/s** | CPU |
| HaiNaSi | Cortex A53 1.5GHz ×4 | 723MB | 585/s | CPU |
| 23049RAD8C | 2.3GHz ×4 + 556MHz ×4 | 15GB | 997/s | WiFi/USB |
| M5 Note | A53 2.0GHz ×8 | 3GB | 1,132/s | WiFi |

## 结论

1. RM2100 受限于 126MB RAM 和 880MHz MIPS CPU，**不适合作为高并发 AI API 网关**
2. 纯透明代理场景（不跑 NewAPI 管理端）仍可胜任
3. 建议用途：旁路由模式，处理低并发个人/家庭 AI 请求
4. 所有测试均在 tmpfs 中进行，重启路由器即可完全还原
5. 压测数据应标注数据库类型（本地 SQLite vs 远程 MySQL）