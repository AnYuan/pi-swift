# PRD: pi-swift Parity with pi-mono (Functional Baseline)

## 1. Purpose

This PRD defines the goal of `pi-swift`: reimplement the TypeScript functionality from `../pi-mono` in Swift while preserving behavior and avoiding regressions.

This document is the feature inventory and acceptance baseline, not an implementation design document.

## 2. Goals and Scope

### 2.1 Overall Goal

- Deliver Swift implementations with equivalent core capabilities and user experience to `../pi-mono` (incrementally by phase)
- Establish testable verification and regression protection for each feature area
- Keep documentation and implementation synchronized throughout migration

### 2.2 Feature Parity Principles

- Prioritize behavioral parity over line-by-line translation
- Keep outputs, errors, and edge-case handling as consistent as possible
- For platform differences (Node.js / Browser / Slack / SSH / Web Components), Swift equivalents are allowed as long as feature semantics are preserved

### 2.3 Non-Goals (Current)

- Adding new original features before baseline parity is complete
- Intentionally changing user-visible behavior just to be “more Swifty” unless explicitly documented and approved

## 3. Success Criteria (Acceptance)

- Each module’s functionality is verified by corresponding tests
- Critical behaviors have regression tests
- Core logic coverage is as close to 100% as practical
- Build and test steps are repeatable in a standard environment
- Task status in `docs/PLAN.md` is updated only after verification passes

## 4. Reference Baseline (Source of Truth)

- Local reference repository: `../pi-mono`
- Identified top-level packages (7):
  - `ai`
  - `agent`
  - `coding-agent`
  - `mom`
  - `pods`
  - `tui`
  - `web-ui`

## 5. Feature Inventory (By Package)

Note: This initial inventory is derived from README files, source entry points, and test coverage distribution. It is intended for phase planning and will be refined in module docs during implementation.

### 5.1 `@mariozechner/pi-ai` (Unified LLM API)

Target functionality:

- Unified multi-provider interface (OpenAI / Anthropic / Google / Vertex / Bedrock / OpenAI-compatible APIs, etc.)
- Model registry and model lookup (built-ins, discovery, selection)
- Streaming output (text/thinking/tool calls/tool results event streams)
- Non-streaming completion APIs
- Tool calling (including parameter schemas, validation, normalization)
- Context objects, context serialization, and cross-provider handoff
- Thinking/reasoning configuration and budgets
- Token / cost / usage tracking (inferred from tests and README)
- OAuth helpers (OpenAI Codex / Copilot / Gemini CLI / Antigravity, etc.)
- Provider adapters and message-format transformation
- Utility functions (event-stream parsing, JSON parsing, overflow handling, validation, Unicode sanitization, etc.)
- Performance: pre-compiled regex patterns for overflow detection

Visible baseline evidence:

- `../pi-mono/packages/ai/src/*`
- `../pi-mono/packages/ai/test/*` (about 34 test files)

### 5.2 `@mariozechner/pi-agent-core` (Agent Runtime)

Target functionality:

- Stateful agent runtime (system prompt, model, messages, tools, stream state)
- Agent loop (LLM call -> tool execution -> next round)
- Event stream (agent/turn/message/tool execution lifecycle events)
- `prompt()` and `continue()` execution model
- `convertToLlm` / `transformContext` context transformation pipeline
- Custom stream function / transport / retry strategy
- Provider integration settings such as thinking budgets and sessionId
- Tool-call state management (pending tool calls)
- Concurrency modernization: async tool execution protocol, parallel independent tool execution via TaskGroup, actor-based event streams

Visible baseline evidence:

- `../pi-mono/packages/agent/src/*`
- `../pi-mono/packages/agent/test/*`

### 5.3 `@mariozechner/pi-tui` (Terminal UI Library)

Target functionality:

- Terminal UI container and differential rendering (flicker-free updates)
- Input/editor components (`Editor` / `Input`)
- Markdown rendering component
- Text / truncated text / layout components (`Box`, `Spacer`, etc.)
- Interactive components such as `SelectList` / `SettingsList`
- Overlay system (positioning, sizing, visibility, stack management)
- Keyboard events / key mapping / input buffering
- Autocomplete (paths / commands)
- Image rendering (Kitty/iTerm terminal image protocols, etc.)
- Editing helpers (`undo`, kill-ring)
- Resource bounds: kill ring and undo stack size limits to prevent unbounded memory growth

Visible baseline evidence:

- `../pi-mono/packages/tui/src/*`
- `../pi-mono/packages/tui/test/*` (about 22 test files)

### 5.4 `@mariozechner/pi-coding-agent` (Interactive Coding Agent CLI)

Target functionality (highest-priority product surface):

- CLI argument parsing and help system
- Multiple runtime modes:
  - interactive
  - print/text
  - json
  - rpc
  - SDK embedding capability (as indicated by README/docs)
- Built-in tool system (at minimum `read`, `bash`, `edit`, `write`, plus `grep`/`find`/`ls`)
- Session management:
  - session storage
  - resume/continue
  - tree / branching
  - compaction (including auto-compaction queue)
- Model selection and provider integration
- Auth storage (API keys / OAuth token storage)
- Resource loading (skills / prompt templates / themes / extensions)
- Extension system and extension flags
- System prompt construction and default prompt
- Interactive TUI (status bar, selectors, keybindings, message stream)
- File processing and attachments (including images and clipboard image handling)
- Export (for example, HTML export)
- Settings management, config selection, slash commands
- Correctness: pipe-safe bash tool (prevents deadlock on large output), unified overflow detection reusing PiAI patterns, improved token estimation for code content, shared path resolution for tools

Visible baseline evidence:

- `../pi-mono/packages/coding-agent/src/*`
- `../pi-mono/packages/coding-agent/test/*` (about 73 test files)
- `../pi-mono/packages/coding-agent/docs/*`

### 5.5 `@mariozechner/pi-web-ui` (Web Chat UI Components)

Target functionality:

- Web Components-based chat UI (message stream, input, message list)
- Integration with `pi-agent-core` / `pi-ai`
- Session and storage support (IndexedDB backend)
- Dialogs for settings, API keys, model selection, etc.
- Attachment preview and document extraction (PDF/DOCX/XLSX/PPTX, etc.)
- Artifact display and sandboxed iframe execution
- Custom provider / OpenAI-compatible provider configuration
- Frontend tool registration (JS REPL, document extraction, renderer registry)

Visible baseline evidence:

- `../pi-mono/packages/web-ui/src/*`
- `../pi-mono/packages/web-ui/README.md`

### 5.6 `@mariozechner/pi-mom` (Slack Bot)

Target functionality:

- Slack Socket Mode bot integration
- Delegation of messages to pi coding agent / agent runtime
- Tool execution (`bash` / `read` / `write` / `edit` / `attach` / `truncate`)
- Working-directory context and persistent store
- Event system (scheduled / periodic tasks)
- Docker / host sandbox modes
- Download / attachments / logging helper capabilities

Visible baseline evidence:

- `../pi-mono/packages/mom/src/*`
- `../pi-mono/packages/mom/docs/*`
- `../pi-mono/packages/mom/README.md`

### 5.7 `@mariozechner/pi` (pods / GPU Model Deployment CLI)

Target functionality:

- GPU pod management (`setup` / `list` / `active` / `remove` / `shell` / `ssh`)
- Model lifecycle management (`start` / `stop` / `list` / `logs`)
- vLLM configuration and known-model presets
- Multi-GPU / context-window / memory parameter configuration
- Remote SSH execution and script distribution
- Integration with agent/chat test entry point (`pi agent`)
- Local configuration management (pod/model configuration)

Visible baseline evidence:

- `../pi-mono/packages/pods/src/*`
- `../pi-mono/packages/pods/README.md`

## 6. Cross-Module Capabilities (Require Unified Design)

- Unified event model (streaming and lifecycle events)
- Tool-calling protocol and parameter validation
- Message / context / attachment models
- Configuration and credential storage
- Session persistence and migrations
- Test fixtures and golden data
- Error categories, retries, timeouts, cancellation (Abort)

## 7. Compatibility and Regression Requirements

- Create comparison tests for each migrated feature (TS baseline behavior vs Swift implementation)
- Maintain golden fixtures for critical paths (inputs, event sequences, outputs)
- Regression policy:
  - Every bug fix must include a test
  - Interface changes must update PRD/PLAN/module docs
  - Newly discovered `pi-mono` feature scope must be added to PRD before scheduling in PLAN

## 8. Internal Quality Improvements (P7)

P7 addresses internal code quality, correctness, and modernization concerns discovered during codebase audit. These changes do not add new user-visible features but improve reliability, resource safety, and codebase maintainability.

Priority order:

1. Bug fixes (pipe deadlock, overflow pattern divergence)
2. Resource safety (bounded collections)
3. Code hygiene (deduplication, estimation accuracy, regex compilation)
4. Modernization (async protocols, parallel execution, actor migration)

## 9. Risks and Notes

- `pi-mono` is a monorepo with strong cross-package dependencies; migration order must follow the dependency chain
- Some functionality depends on Node.js / Browser / Slack / SSH ecosystems and requires Swift platform-equivalent abstractions
- OAuth / provider API behavior changes frequently; adapter isolation plus regression tests are required

## 10. PRD Maintenance Rules

- PRD defines what should be implemented; it does not track task completion status
- Task breakdown and status tracking live in `docs/PLAN.md`
- Module implementation details and acceptance examples should accumulate in `docs/modules/*.md`
