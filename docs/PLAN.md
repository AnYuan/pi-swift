# PLAN: pi-swift 迁移执行计划（基于 PRD）

## 1. 使用规则（必须先读）

本计划用于拆解最小可执行任务，并管理状态与验证证据。

状态更新规则（强制）：

- 不要自己提前更新任务完成状态。
- 只有在“测试通过 + 编译通过 + 文档更新完成”后，才能把任务标记为完成。
- 如果未验证，状态必须保持 `TODO` / `BLOCKED` / `READY_FOR_VERIFY`，不能标记 `DONE`。

## 2. 状态定义

- `TODO`：未开始
- `IN_PROGRESS`：正在实现（仅实际开始编码后使用）
- `READY_FOR_VERIFY`：实现完成，等待测试/编译/回归验证
- `DONE`：已验证通过（测试 + 编译 + 文档已更新）
- `BLOCKED`：被依赖、环境或外部条件阻塞

说明：默认只允许同时有一个 `IN_PROGRESS` 任务，避免并行改动扩大回归面。

## 3. 标准工作流（每个任务都一样）

1. 查看未完成任务（`TODO` / `BLOCKED` 解除后）并 pick one。
2. 先阅读 `../pi-mono` 对应代码、README、测试。
3. 先写测试（或先建立对照 fixture / golden）。
4. 写 Swift 实现。
5. 跑测试。
6. 跑编译检查。
7. 自我 review（逻辑、错误处理、命名、性能、并发）。
8. 更新 `docs/` 对应模块文档。
9. 记录验证证据。
10. 仅此时更新任务状态为 `DONE`。

## 4. 任务记录模板（复制使用）

```md
### TASK-ID: <short-name>
- Status: TODO
- Phase: P<n>
- Depends On: <task ids / none>
- Scope:
  - ...
- Test Plan:
  - ...
- Verification (fill after pass):
  - Tests:
  - Build:
  - Regression:
  - Docs updated:
```

## 5. Phase 拆解（初版）

## P0 文档与基线冻结（先完成文档，再开始编码）

### P0-1: 建立项目执行规范（AGENTS）
- Status: TODO
- Depends On: none
- Scope:
  - 创建项目级 `AGENTS.md`
  - 固化任务状态更新门禁与执行循环
- Test Plan:
  - 文档审阅（无代码测试）

### P0-2: 建立 PRD（功能清单）
- Status: TODO
- Depends On: none
- Scope:
  - 基于 `../pi-mono` 梳理 package 级功能清单
  - 标记核心/外围能力与回归要求
- Test Plan:
  - 文档审阅（无代码测试）

### P0-3: 建立整体架构文档（含架构图）
- Status: TODO
- Depends On: none
- Scope:
  - 建立目标 Swift 模块映射
  - 输出整体架构图与依赖边界
- Test Plan:
  - 文档审阅（无代码测试）

### P0-4: 建立迁移计划与任务状态规则
- Status: TODO
- Depends On: P0-1, P0-2, P0-3
- Scope:
  - 建立 `docs/PLAN.md`
  - 明确 phase 顺序与任务模板
- Test Plan:
  - 文档审阅（无代码测试）

## P1 工程基础设施（Swift 侧）

### P1-1: SwiftPM/Xcode 工程骨架与模块边界
- Status: TODO
- Depends On: P0-1, P0-2, P0-3, P0-4
- Scope:
  - 创建 Swift 包/模块结构（与 `pi-mono` package 映射）
  - 定义基础 target、test target
- Test Plan:
  - `swift build`
  - 空测试目标可运行

### P1-2: 共享测试工具与 fixture/golden 基础设施
- Status: TODO
- Depends On: P1-1
- Scope:
  - 统一测试 helper、fixture loader、golden assertion
  - 建立对照测试目录规范
- Test Plan:
  - helper 单测
  - fixture 读写与 golden diff 测试

### P1-3: 跨模块基础类型（消息/事件/工具 schema 基础）
- Status: TODO
- Depends On: P1-1, P1-2
- Scope:
  - 先落最小共享数据模型，用于后续 `pi-ai` / `agent`
- Test Plan:
  - 编解码与等值单测

## P2 `pi-ai` 迁移（核心依赖）

### P2-1: `pi-ai` 基础类型与模型注册表（最小闭环）
- Status: TODO
- Depends On: P1-3
- Scope:
  - provider/model 基础类型
  - 模型查找/解析最小能力
- Test Plan:
  - 模型查找、错误路径、模糊匹配规则测试

### P2-2: 统一消息上下文与 stream 事件模型
- Status: TODO
- Depends On: P2-1
- Scope:
  - context/messages/tool call/result/thinking 事件结构
- Test Plan:
  - 事件序列序列化/反序列化测试
  - 边界字段测试

### P2-3: JSON / event-stream / validation 工具函数
- Status: TODO
- Depends On: P2-2
- Scope:
  - 流解析、partial JSON、校验辅助、overflow 处理
- Test Plan:
  - 对照 `pi-mono` 同类边界 case

### P2-4: OpenAI Responses 适配（首个 provider）
- Status: TODO
- Depends On: P2-2, P2-3
- Scope:
  - 首个 provider 适配，跑通 tool calling 与流式文本
- Test Plan:
  - mock provider 测试
  - 事件流顺序测试

### P2-5: Anthropic 适配
- Status: TODO
- Depends On: P2-4
- Scope:
  - 消息/工具/thinking 映射
- Test Plan:
  - tool 名称与参数规范化回归测试

### P2-6: Google/Vertex 系列适配
- Status: TODO
- Depends On: P2-4
- Scope:
  - Google/Gemini/Vertex 消息与事件处理
- Test Plan:
  - 缺参 tool call、空流、thinking signature 等回归测试

### P2-7: OAuth 与 provider credential 辅助
- Status: TODO
- Depends On: P2-4
- Scope:
  - OAuth helper 抽象与 token 注入机制
- Test Plan:
  - token 生命周期与错误路径测试

### P2-8: `pi-ai` 回归测试补齐与覆盖率冲刺
- Status: TODO
- Depends On: P2-5, P2-6, P2-7
- Scope:
  - 对齐 `../pi-mono/packages/ai/test` 关键行为
  - 覆盖率尽量接近 100%
- Test Plan:
  - 模块完整测试
  - 覆盖率报告

## P3 `pi-agent-core` 迁移

### P3-1: AgentState / AgentMessage / AgentEvent 类型
- Status: TODO
- Depends On: P2-2
- Scope:
  - 迁移状态模型与事件类型
- Test Plan:
  - 类型行为与状态初始化测试

### P3-2: agent loop（单轮）
- Status: TODO
- Depends On: P3-1, P2-4
- Scope:
  - 单次 prompt -> stream assistant message
- Test Plan:
  - 事件顺序测试

### P3-3: tool execution loop（多轮）
- Status: TODO
- Depends On: P3-2
- Scope:
  - 工具调用执行、tool result 注入、后续轮次继续
- Test Plan:
  - 多轮事件序列与 pending tool calls 测试

### P3-4: continue/retry/abort/sessionId/thinkingBudgets
- Status: TODO
- Depends On: P3-3
- Scope:
  - 补齐 runtime 控制能力
- Test Plan:
  - abort、continue、重试上限测试

### P3-5: `pi-agent-core` 回归测试补齐
- Status: TODO
- Depends On: P3-4
- Scope:
  - 对齐 `../pi-mono/packages/agent/test`
- Test Plan:
  - 模块完整测试 + 覆盖率

## P4 `pi-tui` 迁移

### P4-1: 终端抽象 + 渲染缓冲 + 差分渲染
- Status: TODO
- Depends On: P1-2
- Scope:
  - TUI 核心渲染循环
- Test Plan:
  - 渲染差分与覆盖写回归测试

### P4-2: 输入/编辑器/按键系统
- Status: TODO
- Depends On: P4-1
- Scope:
  - Input/Editor/keys/undo/kill-ring
- Test Plan:
  - 键盘输入编辑行为测试

### P4-3: 列表/Overlay/布局组件
- Status: TODO
- Depends On: P4-1
- Scope:
  - SelectList / SettingsList / Overlay options
- Test Plan:
  - overlay 定位与可见性测试

### P4-4: Markdown/图片/自动补全
- Status: TODO
- Depends On: P4-1
- Scope:
  - markdown 渲染、终端图片、autocomplete
- Test Plan:
  - markdown wrapping、图片协议、路径补全测试

### P4-5: `pi-tui` 回归测试补齐
- Status: TODO
- Depends On: P4-2, P4-3, P4-4
- Scope:
  - 对齐 `../pi-mono/packages/tui/test`
- Test Plan:
  - 模块完整测试 + 覆盖率

## P5 `pi-coding-agent` 迁移（核心产品）

### P5-1: CLI args/help 与最小启动流程
- Status: TODO
- Depends On: P3-5, P4-5
- Scope:
  - args parser、help、入口 main、模式选择最小闭环
- Test Plan:
  - args/help 单测与 smoke test

### P5-2: 内置工具协议与基础工具（read/write/edit/bash）
- Status: TODO
- Depends On: P5-1, P3-5
- Scope:
  - 工具注册/调度，先打通四个核心工具
- Test Plan:
  - 工具行为对照测试
  - 错误路径测试

### P5-3: Session 管理（save/resume/continue）
- Status: TODO
- Depends On: P5-1
- Scope:
  - session 存储、读取、resume 选择基础能力
- Test Plan:
  - 文件操作、时间戳、迁移测试

### P5-4: Session tree / branching / traversal
- Status: TODO
- Depends On: P5-3
- Scope:
  - 分支会话树与导航
- Test Plan:
  - branching/tree traversal 回归测试

### P5-5: Compaction（含自动 compaction 队列）
- Status: TODO
- Depends On: P5-3, P3-5
- Scope:
  - compaction 流程、策略、自动触发队列
- Test Plan:
  - compaction fixtures 与回归测试

### P5-6: Skills / Prompt Templates / Themes / Extensions 发现与加载
- Status: TODO
- Depends On: P5-1
- Scope:
  - 资源发现、frontmatter、冲突与校验规则
- Test Plan:
  - fixture 驱动回归测试（技能冲突、非法 frontmatter 等）

### P5-7: Settings / Auth Storage / Model Registry & Resolver
- Status: TODO
- Depends On: P5-1, P2-8
- Scope:
  - 设置、凭证、模型解析与选择逻辑
- Test Plan:
  - settings/auth/model resolver 回归测试

### P5-8: Interactive TUI 模式与关键交互（状态栏、选择器、快捷键）
- Status: TODO
- Depends On: P5-3, P5-6, P4-5
- Scope:
  - 交互 UI 核心流程
- Test Plan:
  - 交互状态与渲染行为测试

### P5-9: RPC / JSON / Print / SDK 模式
- Status: TODO
- Depends On: P5-1, P5-2, P5-3
- Scope:
  - 非交互模式与程序化集成能力
- Test Plan:
  - 模式输出与协议测试

### P5-10: 附件/图像处理/导出能力
- Status: TODO
- Depends On: P5-2, P5-8
- Scope:
  - 文件参数、图像处理、导出（HTML 等）
- Test Plan:
  - 附件与图像处理回归测试

### P5-11: `pi-coding-agent` 回归测试补齐与覆盖率冲刺
- Status: TODO
- Depends On: P5-4, P5-5, P5-6, P5-7, P5-8, P5-9, P5-10
- Scope:
  - 对齐 `../pi-mono/packages/coding-agent/test` 关键行为
- Test Plan:
  - 模块完整测试 + 覆盖率

## P6 外围能力迁移（按依赖与平台逐步推进）

### P6-1: `pi-web-ui` 功能映射与 Swift 平台等价方案设计
- Status: TODO
- Depends On: P2-8, P3-5
- Scope:
  - 明确 Web Components 功能如何在 Swift（SwiftUI/WebView/客户端）落地
- Test Plan:
  - 设计评审与样例验证

### P6-2: `pi-mom`（Slack bot）迁移
- Status: TODO
- Depends On: P3-5, P5-11
- Scope:
  - Slack 接入、工具委托、sandbox 抽象
- Test Plan:
  - mock Slack 事件与命令执行测试

### P6-3: `pods`（GPU pod CLI）迁移
- Status: TODO
- Depends On: P3-5
- Scope:
  - CLI、SSH、模型生命周期、配置管理
- Test Plan:
  - 配置与命令生成测试、集成 smoke test

## 6. 文档同步任务（持续执行）

每完成任一任务，追加/更新对应模块文档（建议）：

- `docs/modules/pi-ai.md`
- `docs/modules/pi-agent-core.md`
- `docs/modules/pi-tui.md`
- `docs/modules/pi-coding-agent.md`
- `docs/modules/pi-web-ui.md`
- `docs/modules/pi-mom.md`
- `docs/modules/pi-pods.md`

这些文档应至少包含：

- 已实现功能
- 与 `pi-mono` 对齐情况
- 已知差异（如果有）
- 测试覆盖与回归点

## 7. 当前执行入口（下一步）

开始编码前，先完成 P0 文档基线并确认无歧义。之后从 `P1-1` 开始，严格按“先测试后实现”的节奏推进。

