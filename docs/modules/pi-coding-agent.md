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

Tests added:

- registry definition listing and dispatch
- `read` success + truncation details
- `read` offset-beyond-EOF error
- `write` parent-directory creation and file output
- unknown tool error
- `edit` success diff details + no-match + multi-match errors
