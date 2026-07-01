# AI 开发 Harness 设计

## 一、核心痛点共识
- AI 编程现状：生成容易，修改极难。AI 视代码为线性文本，人类视代码为二维空间。
- 软件真正敌人：耦合度与隐式上下文（如 Spring 的式注入、运行时魔法）。

## 二、终极方法论：反魔法，画图取代写代码
- 语言本质有损压缩脑中的三维逻辑。
- 程序本质：约束快照。
- 系统本质：状态与事件的博弈核心操作：放弃堆砌 Service，改为维护状态图。YAML/表格即源码，代码仅为渲染产物。
## 三、三层物理架构（告别 Controller/Service/Mapper）
1. **函数层（Domain）**：纯业务规则，零外部依赖，仅做计算，输入输出显式传递。
2. **适配层（Infra）**：对接外部世界（DB/HTTP/MQTT）。
3. **胶水层（App/Main）**：显式编排，手动组装依赖，消灭 @Autowired 和 init()。

## 四、性能与高并发硬核解法
- 纯函数改为传入指针 + sync.Pool 复用对象，消灭 GC 压力。
- 状态机编译为整数常量二维数组，走 CPU 指令级查表，拒绝运行时反射/Map。

## 五、框架致命边界
- **适合**：业务可穷举、延迟容忍>1ms、团队≤5人、无强制全局初始化。
- **不适合**：高频交易、混沌 AI Agent、强依赖遗留 C 库（此时可合法放弃纯净教条） 六、不恶心框架的最终形态无魔法注解、无全局变量、无自动扫描。
- 目录结构：specs/（画板）+ domain/（纯函数）+ infra/（实现）+ main.go（显式组装）。
- 改业务：改 specs 下状态 YAML，AI 重生成代码改技术：仅改 infra，domain 毫不知情 七、Harness 设计（框架约束 + Harness 发力）
Harness 是套在 AI 脖子上的缰绳+验证器，解决“AI 写的东西怎么保证没错”。

### 1. Specs 校验器（Pre-generation）
- 检查 YAML 状态图完备性（无死锁、无不可达状态、类型匹配）工具：CUE / TypeSpec / 自定义 AST walker作用：AI 动手前拦掉需求错误。\2. 生成后静态门禁（Post-generation）
- 强制 lint + typecheck + import 白名单（domain 禁 import infra/http/sql）。
- 工具：golangci-lint / rustc / 自定义规则引擎。
- 作用：确保生成代码不破坏三层架构边界。\3. 节点级契约测试（Per-node）
- 基于 specs 前置/后置条件自动生成 property-based test。\：Go testing/quickcheck / Rust proptest。
单节点修改即时验证行为合规性。
### 4. Diff 审计钩子（Human-in-the-loop）
- 自动高亮生成差异，标注是否超出 specs 允许范围。
- 工具：git diff + 自定义注解器。
人只看变化点，review 效率拉满 八、人机协作终极形态
上层：人类用 specs 写意图（零代码、纯逻辑、可版本化）下层：AI 翻译为实现（零决策、纯执行、可丢弃、可重 中间靠类型系统 + 状态图校验 + 编译门禁卡死。
- 代码不再是资产，specs 才是。
