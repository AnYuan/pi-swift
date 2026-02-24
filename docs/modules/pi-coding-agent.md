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
