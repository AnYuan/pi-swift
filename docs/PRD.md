# PRD: pi-swift 对齐 pi-mono（功能基线）

## 1. 文档目的

本 PRD 用于定义 `pi-swift` 的目标：以 Swift 重建 `../pi-mono` 的 TypeScript 功能，并确保行为一致、无回归。

本文件是功能清单与验收基线，不是实现细节文档。

## 2. 目标与范围

### 2.1 总目标

- 以 Swift 实现与 `../pi-mono` 等价的核心能力与用户体验（按 phase 渐进交付）
- 为每个功能项建立可验证的测试与回归保障
- 在迁移过程中保持文档与实现同步

### 2.2 功能对齐原则

- 优先对齐“行为”，不是逐行翻译代码
- 输出、错误、边界条件尽量保持一致
- 对平台差异（Node.js / Browser / Slack / SSH / Web Components）允许采用 Swift 平台等价方案，但需保留功能语义

### 2.3 非目标（当前）

- 在完成基线对齐前新增原创功能
- 为了“更 Swift 风格”主动改变用户可见行为（除非明确记录并批准）

## 3. 成功标准（验收）

- 各模块功能通过对应测试验证
- 关键行为具备回归测试
- 核心逻辑覆盖率尽量接近 100%
- 编译与测试在标准环境可重复执行
- `docs/PLAN.md` 中任务状态仅在验证通过后更新

## 4. 参考基线（Source of Truth）

- 本地参考仓库：`../pi-mono`
- 当前识别到的顶层 packages（7 个）：
  - `ai`
  - `agent`
  - `coding-agent`
  - `mom`
  - `pods`
  - `tui`
  - `web-ui`

## 5. 功能清单（按 package）

说明：以下为基于 `README`、源码入口、测试分布的初版功能清单，用于 phase 拆解。后续在实现过程中按模块文档持续细化验收样例。

### 5.1 `@mariozechner/pi-ai`（统一 LLM API）

目标功能：

- 多 Provider 统一接口（OpenAI / Anthropic / Google / Vertex / Bedrock / OpenAI-compatible 等）
- 模型注册与模型查询（内置模型、模型发现、选择）
- 流式输出（text/thinking/tool calls/tool results 等事件流）
- 非流式 completion 能力
- Tool calling（含参数 schema、校验、规范化）
- 上下文对象与上下文序列化/跨 provider handoff
- Thinking/Reasoning 相关配置与预算
- Token / cost / usage 统计（从测试与 README 能力推断）
- OAuth 辅助（OpenAI Codex / Copilot / Gemini CLI / Antigravity 等）
- Provider 适配层与消息格式转换
- 通用工具函数（event-stream、JSON 解析、overflow、validation、Unicode 清洗等）

可见证据（基线）：

- `../pi-mono/packages/ai/src/*`
- `../pi-mono/packages/ai/test/*`（约 34 个测试文件）

### 5.2 `@mariozechner/pi-agent-core`（Agent Runtime）

目标功能：

- Stateful agent（系统提示词、模型、消息、工具、流状态）
- Agent loop（LLM 调用 -> tool execution -> 下一轮）
- 事件流（agent/turn/message/tool execution 生命周期事件）
- `prompt()` 与 `continue()` 执行模型
- `convertToLlm` / `transformContext` 上下文转换链
- 自定义 stream 函数 / transport / retry 策略
- thinking budgets、sessionId 等 provider 集成配置
- 工具调用状态管理（pending tool calls）

可见证据（基线）：

- `../pi-mono/packages/agent/src/*`
- `../pi-mono/packages/agent/test/*`

### 5.3 `@mariozechner/pi-tui`（终端 UI 库）

目标功能：

- 终端 UI 容器与差分渲染（flicker-free）
- 输入/编辑器组件（Editor/Input）
- Markdown 渲染组件
- 文本/截断文本/布局组件（Box/Spacer 等）
- SelectList / SettingsList 等交互组件
- Overlay 系统（定位、尺寸、可见性、栈管理）
- 键盘事件/按键映射/输入缓冲
- 自动补全（路径/命令）
- 图片显示（Kitty/iTerm 协议等终端图像能力）
- Undo / kill-ring 等编辑辅助

可见证据（基线）：

- `../pi-mono/packages/tui/src/*`
- `../pi-mono/packages/tui/test/*`（约 22 个测试文件）

### 5.4 `@mariozechner/pi-coding-agent`（交互式编码 Agent CLI）

目标功能（核心交付优先级最高）：

- CLI 参数解析与帮助系统
- 多模式运行：
  - interactive
  - print/text
  - json
  - rpc
  - SDK 嵌入能力（README/docs 指向）
- 内置工具系统（至少 `read`、`bash`、`edit`、`write`，以及 grep/find/ls）
- 会话管理：
  - session 存储
  - resume/continue
  - tree / branching
  - compaction（含自动 compaction 与队列）
- 模型选择与 provider 集成
- 认证存储（API key / OAuth token storage）
- 资源加载（skills / prompt templates / themes / extensions）
- 扩展机制与扩展 flags
- 系统提示词构建与默认提示词
- 交互式 TUI（状态栏、选择器、键绑定、消息流）
- 文件处理与附件（包含图片、剪贴板图像处理）
- 导出（如 HTML export）
- 设置管理、配置选择、slash commands

可见证据（基线）：

- `../pi-mono/packages/coding-agent/src/*`
- `../pi-mono/packages/coding-agent/test/*`（约 73 个测试文件）
- `../pi-mono/packages/coding-agent/docs/*`

### 5.5 `@mariozechner/pi-web-ui`（Web Chat UI 组件）

目标功能：

- 基于 Web Components 的 Chat UI（消息流、输入框、消息列表）
- 与 `pi-agent-core` / `pi-ai` 集成
- 对话会话与存储（IndexedDB 后端）
- 设置、API Key、模型选择等对话框
- 附件预览与文档抽取（PDF/DOCX/XLSX/PPTX 等）
- Artifact 展示与沙箱 iframe
- 自定义 provider/OpenAI-compatible provider 配置
- 前端工具注册（JS REPL、文档抽取、renderer registry）

可见证据（基线）：

- `../pi-mono/packages/web-ui/src/*`
- `../pi-mono/packages/web-ui/README.md`

### 5.6 `@mariozechner/pi-mom`（Slack Bot）

目标功能：

- Slack Socket Mode bot 集成
- 将消息委托给 pi coding agent / agent runtime
- 工具执行（bash/read/write/edit/attach/truncate）
- 工作目录上下文与持久化 store
- 事件系统（定时/周期任务）
- Docker/host sandbox 模式
- 下载/附件/日志等辅助能力

可见证据（基线）：

- `../pi-mono/packages/mom/src/*`
- `../pi-mono/packages/mom/docs/*`
- `../pi-mono/packages/mom/README.md`

### 5.7 `@mariozechner/pi`（pods / GPU 模型部署 CLI）

目标功能：

- GPU pod 管理（setup/list/active/remove/shell/ssh）
- 模型生命周期管理（start/stop/list/logs）
- vLLM 配置与已知模型预设
- 多 GPU/上下文/显存参数配置
- 远程 SSH 执行与脚本分发
- 与 agent/chat 测试入口集成（`pi agent`）
- 本地配置管理（pod/model 配置）

可见证据（基线）：

- `../pi-mono/packages/pods/src/*`
- `../pi-mono/packages/pods/README.md`

## 6. 跨模块能力（需要统一设计）

- 统一事件模型（流式事件、生命周期事件）
- 工具调用协议与参数校验
- 消息模型/上下文模型/附件模型
- 配置与凭证存储
- 会话持久化与迁移
- 测试 fixture 与 golden data
- 错误分类、重试、超时、取消（Abort）

## 7. 兼容性与回归要求

- 对每个已迁移功能建立对照测试（TS 基线行为 vs Swift 实现）
- 对关键路径维护 golden fixtures（输入、事件序列、输出）
- 回归策略：
  - 修 bug 必须补测试
  - 改接口必须更新 PRD/PLAN/模块文档
  - 新发现 `pi-mono` 功能项必须先补入 PRD 再排入 PLAN

## 8. 风险与注意事项

- `pi-mono` 是 monorepo，跨 package 依赖较强，迁移顺序必须遵守依赖链
- 部分能力依赖 Node.js / Browser / Slack / SSH 生态，Swift 需做平台等价抽象
- OAuth / Provider API 行为容易变化，需以可替换适配层 + 回归测试保障

## 9. PRD 维护规则

- PRD 用于定义“应该实现什么”，不记录任务完成状态
- 任务拆解与状态管理统一在 `docs/PLAN.md`
- 模块实现细节与验收样例沉淀到 `docs/modules/*.md`

