# PiCodingAgent Module Progress

## Scope

This document tracks `PiCodingAgent` implementation progress and parity status against `../pi-mono/packages/coding-agent`.

## Implemented

### P5-1: CLI args/help and minimum startup flow

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/CLIArgs.swift`
- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/CLIApp.swift`
- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/PiCodingAgent.swift`
- `/Users/anyuan/Development/pi-swift/Sources/PiSwiftCLI/main.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentCLITests.swift`

Implemented behavior:

- Argument parsing (`PiCodingAgentCLIArgsParser`)
  - `--help`, `--version`, `--print`, `--mode`, `--provider`, `--model`
  - single positional prompt argument
  - structured parse errors (`unknownFlag`, `missingValue`, `invalidMode`, `unexpectedArgument`)
- Help/usage text generation
- Minimum startup mode selection (`PiCodingAgentCLIApp`)
  - help / version early exits
  - default interactive startup
  - `--print` startup
  - `--mode rpc` startup
  - piped stdin forcing print-mode startup
- Executable entry wiring (`pi-swift`)
  - maps CLI result to stdout/stderr and minimal mode startup banner output

## Tests Added

- args parser parsing and error paths
- help/version output behavior
- startup action selection (interactive / print / rpc)
- piped stdin print-mode coercion
- executable smoke via `swift run pi-swift --help`

## Notes / Decisions

- `P5-1` intentionally ports a minimal CLI surface first (args/help/startup-mode orchestration) and defers the full `pi-mono` command set (`install/remove/update/list/config`, extensions, sessions, resume picker) to later `P5` tasks.

## `P5-2` Progress (Built-in Tools Foundation)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/Tools.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentToolsTests.swift`

Implemented in this slice:

- tool protocol + registry/dispatch foundation
  - `PiCodingAgentTool`
  - `PiCodingAgentToolRegistry`
  - `PiCodingAgentToolResult`
  - `PiCodingAgentToolError`
- built-in `read` tool (`PiFileReadTool`)
  - path read under a base directory
  - line-based `offset` / `limit`
  - truncation hint text + `details.truncation`
  - error when offset is beyond EOF
- built-in `write` tool (`PiFileWriteTool`)
  - parent directory creation
  - UTF-8 write + success confirmation text
- built-in `edit` tool (`PiFileEditTool`)
  - unique text replacement in UTF-8 files
  - explicit errors for no match / multiple matches
  - simple diff summary in `details.diff`
- built-in `bash` tool (`PiBashTool`)
  - shell execution via `Process`
  - configurable working directory / shell path / timeout / commandPrefix
  - non-zero exit and timeout error handling
  - merged stdout/stderr capture with max-output truncation flag in details

Tests added:

- registry definition listing and dispatch
- `read` success + truncation details
- `read` offset-beyond-EOF error
- `write` parent-directory creation and file output
- unknown tool error
- `edit` success diff details + no-match + multi-match errors
- `bash` happy path / commandPrefix / non-zero / timeout / missing cwd / invalid shell

## `P5-2` Verification

- `swift test --filter PiCodingAgentTests` passed (24 `PiCodingAgent` tests) on 2026-02-24
- `swift build` passed on 2026-02-24
- `P5-2` scope covered in Swift foundation:
  - tool protocol + registry/dispatch
  - `read`, `write`, `edit`, `bash` core tools

## `P5-3` Progress (Session Management Foundation)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/SessionStore.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentSessionStoreTests.swift`

Implemented in this slice:

- JSON-backed session persistence (`PiCodingAgentSessionStore`)
  - `saveNew(...)`
  - `save(id:...)` with `createdAt` preservation + `updatedAt` refresh
  - `load(id:)`
  - `listSessions()` sorted by `updatedAt` desc
  - `latestSession()`
  - `resolveContinue(sessionID:)` (explicit id or latest session)
- session record model (`PiCodingAgentSessionRecord`) carrying `PiAgentState`
- deterministic test injection hooks (clock + id generator)

Tests added:

- save/load round-trip
- update timestamp semantics
- session listing sort order
- continue resolution (explicit + latest)
- no-sessions error path

## `P5-3` Verification

- `swift test --filter PiCodingAgentTests` passed (29 `PiCodingAgent` tests) on 2026-02-24
- `swift build` passed on 2026-02-24

## `P5-4` Progress (Session Tree / Branching / Traversal)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/SessionTree.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentSessionTreeTests.swift`

Implemented in this slice:

- session tree index persistence (`PiCodingAgentSessionTreeStore`)
  - `createRoot(sessionID:)`
  - `branch(from:childID:)`
  - `node(id:)`
  - `children(of:)`
  - `ancestors(of:)`
  - `pathToRoot(of:)`
- persistent node model (`PiCodingAgentSessionNode`) with parent/children edges
- JSON-backed index file storage and error handling

Tests added:

- root + multi-branch persistence
- children/ancestors/path traversal
- duplicate-node and missing-parent error paths

## `P5-4` Verification

- `swift test --filter PiCodingAgentTests` passed (32 `PiCodingAgent` tests) on 2026-02-24
- `swift build` passed on 2026-02-24

## `P5-5` Progress (Compaction + Auto-Compaction Queue Foundation)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/Compaction.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentCompactionTests.swift`

Implemented in this slice:

- compaction strategy helpers (`PiCodingAgentCompactionEngine`)
  - context token estimation heuristic
  - threshold / overflow auto-compaction decision
  - compaction application (summary message insertion + tail retention)
- compaction log persistence (`PiCodingAgentCompactionLogStore`)
  - append/list/latest per-session compaction entries
- auto-compaction queue (`PiCodingAgentAutoCompactionQueue`)
  - queue while compacting, ordered flush after compaction
- compaction orchestration (`PiCodingAgentCompactionCoordinator`)
  - loads session, decides/executes compaction, saves compacted state, appends compaction log entry

Tests added:

- threshold/overflow trigger detection
- compaction apply result + summary-message injection
- compaction log append/latest persistence
- queue deferral and ordered flush behavior
- coordinator auto-compaction end-to-end persistence/update flow

## `P5-5` Verification

- `swift test --filter PiCodingAgentTests` passed (37 `PiCodingAgent` tests) on 2026-02-24
- `swift build` passed on 2026-02-24

## `P5-6` Progress (Skills / Prompt Templates / Themes / Extensions Resource Loading)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/Resources.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentResourcesTests.swift`
- `/Users/anyuan/Development/pi-swift/Tests/Fixtures/pi-coding-agent/resources/...`

Implemented in this slice:

- resource loader foundation (`PiCodingAgentResourceLoader`)
  - skills / prompt templates / themes / extensions discovery from filesystem paths
  - frontmatter parsing (`PiCodingAgentFrontmatterParser`)
  - duplicate resource handling with diagnostics (`skill` / `prompt` / `theme`)
  - extension conflict detection (`tools`, `commands`, `flags`)
- skill loading rules
  - `SKILL.md` and top-level `.md` discovery
  - resource-name validation
  - required description validation
  - `disable-model-invocation` frontmatter flag parsing
- prompt template loading
  - frontmatter description parsing
  - first-line description fallback (truncated to 60 chars)
  - command arg parsing + `$1`, `$@`, `${@:n}` substitution helpers
- theme loading
  - JSON parsing
  - required `name`
  - required `colors.text` and `colors.background`
- extension discovery/loading
  - standalone `.js` / `.ts`
  - directory `index.js` / `index.ts`
  - `package.json` with `pi.*` resource/command/tool metadata

Tests added:

- frontmatter parse success + malformed frontmatter fallback
- prompt arg parsing and substitution helpers
- skills: invalid name / missing description / duplicate-name diagnostics
- prompts: description fallback + duplicate prompt-name handling
- themes: required-color validation + duplicate theme-name handling
- extensions: standalone + package discovery, metadata mapping, parse failure diagnostics, tool-conflict rejection

## `P5-6` Verification

- `swift test --filter PiCodingAgentTests` passed (44 `PiCodingAgent` tests) on 2026-02-24
- `swift build` passed on 2026-02-24

## `P5-7` Progress (Settings Slice, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/Settings.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentSettingsTests.swift`

Implemented in this slice:

- settings storage backends
  - file-backed settings storage (`PiCodingAgentFileSettingsStorage`)
  - in-memory settings storage (`PiCodingAgentInMemorySettingsStorage`)
- settings manager foundation (`PiCodingAgentSettingsManager`)
  - global + project settings loading
  - recursive deep-merge for nested objects
  - `reload()` with parse-error retention behavior (keeps previous valid settings)
  - `flush()` that preserves externally-added fields by reloading current file before applying modified keys
  - per-scope error tracking via `drainErrors()`
- initial settings getters/setters needed by `pi-coding-agent`
  - `theme`
  - `defaultModel`
  - `defaultThinkingLevel`
  - `shellCommandPrefix`
  - `extensions`
  - `enabledModels`

Tests added:

- global/project deep merge behavior for nested settings objects
- external edits preserved across `flush()` while in-memory changes win for modified keys
- reload invalid-JSON fallback + error draining
- project-scoped theme override persistence + `shellCommandPrefix` getter

Verification (slice):

- `swift test --filter PiCodingAgentSettingsTests` passed on 2026-02-24

## `P5-10` Verification (Completed)

- `swift test --filter PiCodingAgentTests` passed (100 `PiCodingAgent` tests) on 2026-02-24
- `swift build` passed on 2026-02-24
- `P5-10` scope covered in current Swift implementation:
  - file argument processing (`@file` text + image attachment extraction)
  - image-related settings semantics (`images.autoResize`, `images.blockImages`)
  - HTML export foundation for session `.json` files
  - CLI `--export` flow (`--export <session.json> [output.html]`)
- Known remaining parity gap deferred to `P5-11`/future slices:
  - `pi-mono` `.jsonl` export/session format compatibility is not yet implemented

## `P5-11` Verification (Completed)

- `swift test --filter PiCodingAgentTests` passed (100 `PiCodingAgent` tests) on 2026-02-24
- `swift test --enable-code-coverage --filter PiCodingAgentTests` passed on 2026-02-24
- Coverage report generated: `/Users/anyuan/Development/pi-swift/docs/reports/pi-coding-agent-coverage.md`
- Coverage snapshot (`Sources/PiCodingAgent/*`):
  - Regions: `76.49%`
  - Functions: `83.89%`
  - Lines: `86.02%`
- Regression surface now includes:
  - CLI args/startup/execution (`print`/`json`/`rpc`/`--export`)
  - tools (`read`/`write`/`edit`/`bash`)
  - session store/tree
  - settings/auth/model resolver
  - resources loader
  - interactive mode/session
  - file attachment processing and HTML export

## `P5-7` Progress (Auth Storage Slice, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/AuthStorage.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentAuthStorageTests.swift`

Implemented in this slice:

- auth storage backends
  - file-backed auth storage backend (`PiCodingAgentFileAuthStorageBackend`)
  - in-memory auth storage backend (`PiCodingAgentInMemoryAuthStorageBackend`)
- credential model
  - `api_key` credentials
  - OAuth credentials (compatible `type: "oauth"` JSON shape using `PiAIOAuthCredentials`)
- auth storage foundation (`PiCodingAgentAuthStorage`)
  - set/get/remove/list/has
  - runtime API key overrides (for CLI/session injection)
  - provider-derived env key fallback (e.g. `OPENAI_API_KEY`)
  - explicit env-var-name and command (`!cmd`) API key resolution
  - fallback resolver hook for custom providers
  - OAuth API key resolution via `PiAIOAuthCredentialService` with refreshed credential persistence

Tests added:

- CRUD/list behavior for stored credentials
- runtime override precedence over stored literal keys
- env-var-name / command / literal API key resolution
- OAuth refresh path updates in-memory persisted credentials
- `hasAuth` behavior for env-derived and fallback-resolved providers

Verification (slice):

- `swift test --filter PiCodingAgentAuthStorageTests` passed on 2026-02-24

## `P5-7` Progress (Model Registry & Resolver Slice, Completed)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/ModelResolver.swift`
- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/Settings.swift` (extended `defaultProvider`)
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentModelResolverTests.swift`

Implemented in this slice:

- `PiCodingAgentModelRegistry`
  - wraps `PiAIModelRegistry`
  - `getAll()` / `getAvailable()` (auth-filtered via `PiCodingAgentAuthStorage`)
  - provider/model lookup and provider API key passthrough
- `PiCodingAgentModelResolver`
  - CLI provider/model resolution
  - `parseModelPattern(...)` with thinking suffix parsing (`off|minimal|low|medium|high|xhigh`)
  - OpenRouter-style model IDs with embedded `:` handling (exact ID match before thinking suffix split)
  - invalid thinking-level fallback warning behavior
  - initial model selection using settings defaults and provider default map
- `SettingsManager` extension for `defaultProvider` getter/setter

Tests added:

- alias-vs-dated preference for fuzzy model matching
- OpenRouter-style `:` IDs with optional thinking suffix
- invalid thinking suffix warning path
- CLI resolution with explicit provider and `provider/model` patterns
- unknown-provider error path
- auth-filtered available model list + provider API key passthrough
- initial model selection from settings and provider defaults

## `P5-7` Verification (Completed)

- `swift test --filter PiCodingAgentTests` passed (60 `PiCodingAgent` tests) on 2026-02-24
- `swift build` passed on 2026-02-24

## `P5-8` Progress (Interactive Mode Slice 1, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/InteractiveMode.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentInteractiveModeTests.swift`

Implemented in this slice:

- interactive mode foundation (`PiCodingAgentInteractiveMode`)
  - editor-backed prompt entry (`PiTUIEditorComponent`)
  - transcript capture for submitted prompts (foundation)
  - status bar rendering with model + shortcut hints
  - overlay state machine (`none` / `settings` / `modelSelector`)
- shortcut handling (foundation)
  - `F2` toggle settings overlay
  - `F3` open/close model selector
  - `Enter` submit prompt
  - `Esc` close active overlay
- model selector foundation
  - auth-filtered model list preferred (`getAvailable()`), fallback to all models
  - sorted model list navigation (`up/down`)
  - selection updates settings `defaultProvider/defaultModel` and current model

Tests added:

- status bar includes current model and shortcut hints
- settings overlay toggle and escape close
- model selector navigation and selection persistence to settings
- prompt submit updates transcript and clears editor

Verification (slice):

- `swift test --filter PiCodingAgentInteractiveModeTests` passed on 2026-02-24

## `P5-8` Progress (Interactive Mode Slice 2, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/InteractiveMode.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentInteractiveModeTests.swift`

Implemented in this slice:

- raw input routing (`handleInput(_:)`)
  - integrates `PiTUIKeys.parseKey(...)`
  - maps raw shortcuts (`ctrl+s`, `ctrl+p`) to interactive overlays
  - routes arrow keys / enter / escape through the overlay key-state machine
  - falls back to editor input for printable text and other non-shortcut inputs
- overlay interactions via parsed ANSI key sequences
  - arrow navigation in model selector
  - escape close behavior

Tests added:

- raw text + enter submission path via `handleInput(_:)`
- arrow + escape routing inside model selector via ANSI sequences

Verification (slice):

- `swift test --filter PiCodingAgentInteractiveModeTests` passed on 2026-02-24

## `P5-8` Progress (Interactive Mode Slice 3, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/InteractiveMode.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentInteractiveModeTests.swift`

Implemented in this slice:

- component-driven overlays (replacing ad-hoc text overlays)
  - settings overlay now uses `PiTUISettingsList`
  - model selector overlay now uses `PiTUISelectList`
- settings interactions
  - interactive cycling for `theme` and `defaultThinkingLevel`
  - live persistence back into `PiCodingAgentSettingsManager`
  - status-message updates after setting changes
- key-id compatibility retained for tests/manual triggers by translating key IDs to raw terminal input

Tests added:

- settings overlay interaction test validating `theme` and `defaultThinkingLevel` changes via list navigation

Verification (slice):

- `swift test --filter PiCodingAgentInteractiveModeTests` passed on 2026-02-24

## `P5-8` Progress (Interactive Session Runtime Slice, Completed)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/InteractiveSession.swift`
- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/InteractiveMode.swift` (PiTUIComponent conformance)
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentInteractiveSessionTests.swift`

Implemented in this slice:

- `PiCodingAgentInteractiveSession`
  - mounts `PiCodingAgentInteractiveMode` into `PiTUI`
  - start/stop lifecycle
  - input/key forwarding with render requests
- virtual-terminal driven interactive integration coverage
  - initial status bar render
  - prompt submit render updates
  - shortcut-driven overlay activation (`ctrl+s` settings, `ctrl+p` models)

## `P5-8` Verification (Completed)

- `swift test --filter PiCodingAgentTests` passed (71 `PiCodingAgent` tests) on 2026-02-24
- `swift build` passed on 2026-02-24

## `P5-9` Progress (Modes / RPC / SDK Foundation Slice, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/Modes.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentModesTests.swift`

Implemented in this slice:

- `PiCodingAgentModeRunner`
  - deterministic print-mode output formatter (`runPrint`)
  - JSON mode event stream formatter (`runJSON`) using line-delimited JSON events
  - minimal RPC envelope handler (`handleRPC`) with:
    - `ping`
    - `run.print`
    - `run.json`
    - unknown-method error envelope
- `PiCodingAgentSDK` facade for programmatic use
  - `runPrint`
  - `runJSON`
  - `handleRPC`

Tests added:

- print mode deterministic output
- JSON mode structured event emission
- RPC ping result envelope
- RPC `run.print` delegation
- RPC unknown-method error envelope
- SDK facade methods for print/JSON

Verification (slice):

- `swift test --filter PiCodingAgentModesTests` passed on 2026-02-24

## `P5-10` Progress (HTML Export Foundation Slice, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/HTMLExporter.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentHTMLExporterTests.swift`

Implemented in this slice:

- HTML export foundation (`PiCodingAgentHTMLExporter`)
  - renders `PiCodingAgentSessionRecord` into a standalone HTML document
  - displays:
    - session metadata + system prompt
    - user / assistant / tool-result / custom messages
    - embedded image attachments (`data:` URLs)
    - tool-call arguments and tool-result details as formatted JSON
  - HTML escaping for text payloads and JSON blocks
- file export entrypoint
  - exports from current Swift session-store `.json` files
  - default output path (`session.json` -> `session.html`)
  - explicit output path support
  - structured errors for unsupported formats / read / decode / write failures

Tests added:

- HTML render includes escaped text, embedded image, and tool-result details
- export writes default output file and returns path
- export supports explicit output path
- unsupported `.jsonl` input currently rejected (future parity slice)

Verification (slice):

- `swift test --filter PiCodingAgentHTMLExporterTests` passed on 2026-02-24

## `P5-10` Progress (CLI `--export` Integration Slice, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/CLIArgs.swift`
- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/CLIApp.swift`
- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/CLIExecutor.swift`
- `/Users/anyuan/Development/pi-swift/Sources/PiSwiftCLI/main.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentCLITests.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentCLIExecutionTests.swift`

Implemented in this slice:

- CLI parser support for `--export <session.json> [output.html]`
  - stores export input path plus optional output path positional
  - keeps existing prompt parsing behavior when `--export` is absent
- startup action routing
  - `PiCodingAgentStartupAction.exportHTML(inputPath:outputPath:)`
  - `PiCodingAgentCLIApp` prioritizes export mode before interactive/print/json/rpc startup
- executor integration
  - `PiCodingAgentCLIExecutor` invokes `PiCodingAgentHTMLExporter.exportSessionFile(...)`
  - success path prints the exported HTML path
  - exporter failures return non-zero exit code and stderr message
- executable compatibility
  - `PiSwiftCLI/main.swift` updated to handle export action exhaustively

Tests added:

- CLI parser export input/output path parsing
- CLI startup action selection for `--export`
- CLI executor end-to-end export path output + file creation

Verification (slice):

- `swift test --filter 'PiCodingAgentCLITests|PiCodingAgentCLIExecutionTests'` passed on 2026-02-24

## `P5-10` Progress (Image Settings Semantics Slice, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/Settings.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentSettingsTests.swift`

Implemented in this slice:

- image settings getters/setters in `PiCodingAgentSettingsManager`
  - `getImageAutoResize()` (default `true`)
  - `setImageAutoResize(...)`
  - `getBlockImages()` (default `false`)
  - `setBlockImages(...)`
- nested `images.*` persistence using object merge semantics
  - preserves compatibility with existing global/project deep-merge behavior
  - supports project override of only one nested image setting key

Tests added:

- defaults + persistence for `images.autoResize` and `images.blockImages`
- global/project deep-merge behavior for nested `images` object

Verification (slice):

- `swift test --filter PiCodingAgentSettingsTests` passed on 2026-02-24

## `P5-10` Progress (File Argument / Image Attachment Processing Slice, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/FileProcessor.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentFileProcessorTests.swift`

Implemented in this slice:

- file argument processor foundation (`PiCodingAgentFileProcessor`)
  - processes CLI file arguments into:
    - wrapped text payload (`<file name="...">...</file>`)
    - image attachments (`PiAIImageContent`)
  - resolves absolute / relative / `~` paths
  - skips empty files
  - detects common image formats (PNG/JPEG/GIF/WebP/BMP) by signature with extension fallback
  - throws structured errors for missing files, read failures, and non-UTF8 non-image files
- parity note:
  - image auto-resize option is represented in the API but resizing behavior is deferred to a later `P5-10` slice

Tests added:

- text-file wrapping
- image attachment extraction + MIME/base64 encoding
- empty-file skip behavior
- missing-file error path
- non-UTF8 non-image error path
- relative + tilde path resolution

Verification (slice):

- `swift test --filter PiCodingAgentFileProcessorTests` passed on 2026-02-24

## `P5-9` Progress (CLI Non-Interactive Execution Slice, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/CLIArgs.swift`
- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/CLIApp.swift`
- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/CLIExecutor.swift`
- `/Users/anyuan/Development/pi-swift/Sources/PiSwiftCLI/main.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentCLITests.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentCLIExecutionTests.swift`

Implemented in this slice:

- CLI mode surface extended with `--mode json`
  - parser + help text + validation error messages updated
  - startup action extended with `startJSON(...)`
- `PiCodingAgentCLIExecutor`
  - composes `PiCodingAgentCLIApp` + `PiCodingAgentModeRunner`
  - renders `print` and `json` outputs directly into `stdout`
  - handles single-request RPC from piped stdin
  - returns structured invalid-request RPC error envelopes for malformed JSON input
- executable entrypoint integration (`PiSwiftCLI/main.swift`)
  - real stdin/tty detection
  - piped stdin forwarding into `PiCodingAgentCLIExecutor`
  - falls back to legacy placeholder messages only when no protocol output is produced

Tests added:

- CLI parse/startup action for `--mode json`
- CLI invalid mode error text (including `json`)
- CLI executor output for print mode
- CLI executor output for JSON mode
- CLI executor RPC request handling and malformed-request error envelope

Verification (slice):

- `swift test --filter PiCodingAgentCLITests` passed on 2026-02-24
- `swift test --filter PiCodingAgentCLIExecutionTests` passed on 2026-02-24

## `P5-9` Progress (RPC Tool Integration Slice, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/Modes.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentModesTests.swift`

Implemented in this slice:

- RPC tool protocol integration in `PiCodingAgentModeRunner`
  - `tools.list` returns registered tool definitions
  - `tools.execute` executes via `PiCodingAgentToolRegistry` and returns structured result envelope
  - RPC error envelopes for missing tool registry, invalid params, and tool execution failures
- SDK tool facade (`PiCodingAgentSDK`)
  - `listTools()`
  - `executeTool(_:)`

Tests added:

- RPC `tools.list` returns tool definitions
- RPC `tools.execute` runs built-in tools and returns structured results
- SDK tool facade can list and execute tools

## `P5-9` Verification (Completed)

- `swift test --filter PiCodingAgentTests` passed (85 `PiCodingAgent` tests) on 2026-02-24
- `swift build` passed on 2026-02-24
- `swift run pi-swift --mode json hello` emitted structured JSON events on 2026-02-24

## `P5-9` Progress (Modes / RPC / SDK Foundation Slice, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiCodingAgent/Modes.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiCodingAgentTests/PiCodingAgentModesTests.swift`

Implemented in this slice:

- mode runner foundation (`PiCodingAgentModeRunner`)
  - deterministic `print` mode output
  - newline-delimited `json` mode event output (`mode.start`, `input`, `result`)
- RPC foundation
  - request envelope parsing (`id`, `method`, `params`)
  - `ping`
  - `run.print`
  - `run.json`
  - method-not-found error envelope
- SDK facade foundation (`PiCodingAgentSDK`)
  - `runPrint(...)`
  - `runJSON(...)`
  - `handleRPC(...)`

Tests added:

- print mode output shape
- JSON mode event stream shape
- RPC `ping` result envelope
- RPC `run.print` delegation
- RPC unknown-method error envelope
- SDK facade accessors for print/json modes

Verification (slice):

- `swift test --filter PiCodingAgentModesTests` passed on 2026-02-24

### P7-1: Bash tool pipe deadlock fix

Files:

- `Sources/PiCodingAgent/Tools.swift`
- `Tests/PiCodingAgentTests/PiCodingAgentToolsTests.swift`

Implemented behavior:

- Fixed pipe deadlock in `PiBashTool.execute()` where `readDataToEndOfFile()` was called after waiting for process termination
- If process output exceeded the OS pipe buffer (~64KB on macOS), the child blocked on `write()` while the parent blocked on `sema.wait()`
- Now dispatches `readDataToEndOfFile()` on a background queue before waiting for termination, using `DispatchGroup` to sync read completion
- Timeout and error handling paths also wait for the read to finish before returning

Tests added:

- `testBashToolHandlesLargeOutputWithoutDeadlock`: runs `seq 1 100000` (~588KB output), verifies completion and content correctness

Verification:

- `swift test --filter PiCodingAgentToolsTests` passed (15 tests) on 2026-02-27

### P7-2: Overflow detection divergence fix

Files:

- `Sources/PiCodingAgent/Compaction.swift`
- `Tests/PiCodingAgentTests/PiCodingAgentCompactionTests.swift`

Implemented behavior:

- Replaced weak 3-pattern overflow detection in `isContextOverflowSignal()` with delegation to `PiAIOverflow.patterns()` (15 regex patterns)
- Added HTTP 400/413 status code check for full parity with `PiAIOverflow.isContextOverflow`
- Compaction now detects all overflow signals that the AI layer detects

Tests added:

- `testOverflowDetectionCoversAllPiAIOverflowPatterns`: verifies all 15 patterns + HTTP status codes trigger overflow compaction

Verification:

- `swift test --filter PiCodingAgentCompactionTests` passed (6 tests) on 2026-02-27

### P7-4: Deduplicate path resolution

Files:

- `Sources/PiCodingAgent/Tools.swift`

Implemented behavior:

- Extracted shared `resolvePath(_:relativeTo:)` file-private function
- Removed duplicated path resolution from `PiFileReadTool`, `PiFileWriteTool`, `PiFileEditTool`
- Pure refactor with zero behavioral change

Verification:

- `swift test --filter PiCodingAgentToolsTests` passed (15 tests) on 2026-02-27
