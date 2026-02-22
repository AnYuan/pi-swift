# PLAN: pi-swift Migration Execution Plan (Based on PRD)

## 1. Usage Rules (Read First)

This plan is used to break work into the smallest executable tasks and track status plus verification evidence.

Mandatory status update rule:

- Do not update task completion status in advance.
- A task may be marked complete only after tests pass, compilation passes, and documentation updates are done.
- If not verified, status must remain `TODO`, `BLOCKED`, or `READY_FOR_VERIFY` and must not be marked `DONE`.
- All implemented changes must be committed atomically (one coherent change per commit).

## 2. Status Definitions

- `TODO`: not started
- `IN_PROGRESS`: implementation is actively underway (use only after coding begins)
- `READY_FOR_VERIFY`: implementation is done, waiting for test/build/regression verification
- `DONE`: verification passed (tests + build + docs updated)
- `BLOCKED`: blocked by dependency, environment, or external condition

Note: By default only one task should be `IN_PROGRESS` at a time to reduce regression risk from parallel changes.

## 3. Standard Workflow (Same for Every Task)

1. Review unfinished tasks (`TODO`, or unblocked items) and pick one.
2. Read the corresponding code, README, and tests in `../pi-mono`.
3. Write tests first (or establish comparison fixtures/goldens first).
4. Implement in Swift.
5. Run tests.
6. Run compile checks.
7. Self-review (logic, error handling, naming, performance, concurrency).
8. Update the corresponding module docs under `docs/`.
9. Record verification evidence.
10. Only then update the task status to `DONE`.
11. Create an atomic commit for the completed change (do not bundle unrelated work).

## 4. Task Record Template (Copy/Use)

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

## 5. Phase Breakdown (Initial)

## P0 Documentation and Baseline Freeze (Complete docs before coding)

### P0-1: Establish project execution rules (AGENTS)
- Status: DONE
- Depends On: none
- Scope:
  - Create project-level `AGENTS.md`
  - Lock task-status gate rules and execution loop
- Test Plan:
  - Document review (no code test)
- Verification:
  - Docs reviewed and committed in `docs: initialize PRD, plan, and architecture` and follow-up English/rules docs commit on 2026-02-22

### P0-2: Create PRD (feature inventory)
- Status: DONE
- Depends On: none
- Scope:
  - Build package-level feature inventory from `../pi-mono`
  - Mark core vs peripheral capabilities and regression requirements
- Test Plan:
  - Document review (no code test)
- Verification:
  - `docs/PRD.md` created from local `../pi-mono` package/source/test scan and reviewed on 2026-02-22

### P0-3: Create architecture doc (with diagram)
- Status: DONE
- Depends On: none
- Scope:
  - Define target Swift module mapping
  - Produce high-level architecture diagram and dependency boundaries
- Test Plan:
  - Document review (no code test)
- Verification:
  - `docs/ARCHITECTURE.md` created with Mermaid diagram and module dependency order; reviewed on 2026-02-22

### P0-4: Create migration plan and task status rules
- Status: DONE
- Depends On: P0-1, P0-2, P0-3
- Scope:
  - Create `docs/PLAN.md`
  - Define phase order and task template
- Test Plan:
  - Document review (no code test)
- Verification:
  - `docs/PLAN.md` created and later updated with English/atomic-commit policy on 2026-02-22

## P1 Swift-side Infrastructure

### P1-1: SwiftPM/Xcode project skeleton and module boundaries
- Status: DONE
- Depends On: P0-1, P0-2, P0-3, P0-4
- Scope:
  - Create Swift package/module structure (mapped to `pi-mono` packages)
  - Define base targets and test targets
- Test Plan:
  - `swift build`
  - Empty test targets can run
- Verification:
  - Tests: `swift test` passed (8 smoke tests) on 2026-02-22
  - Build: `swift build` passed on 2026-02-22
  - Regression: N/A (initial scaffold only; validated target graph and imports via smoke tests)
  - Docs updated: `README.md`, `docs/modules/project-infrastructure.md`, `docs/PLAN.md`

### P1-2: Shared test utilities and fixture/golden infrastructure
- Status: DONE
- Depends On: P1-1
- Scope:
  - Standardize test helpers, fixture loaders, golden assertions
  - Define comparison test directory conventions
- Test Plan:
  - Unit tests for helpers
  - Fixture I/O and golden diff tests
- Verification:
  - Tests: `swift test` passed (13 tests total, including `PiTestSupportTests`) on 2026-02-22
  - Build: `swift build` passed on 2026-02-22
  - Regression: N/A (infrastructure task; helper behavior validated by fixture/golden tests)
  - Docs updated: `README.md`, `docs/modules/testing-infrastructure.md`, `docs/PLAN.md`

### P1-3: Cross-module foundational types (messages/events/tool schema base)
- Status: DONE
- Depends On: P1-1, P1-2
- Scope:
  - Implement the minimum shared data model for later `pi-ai` / `agent` work
- Test Plan:
  - Encoding/decoding and equality unit tests
- Verification:
  - Tests: `swift test` passed (16 tests total, including new `PiCoreTypesCodableTests`) on 2026-02-22
  - Build: `swift build` passed on 2026-02-22
  - Regression: N/A (foundational type additions; stable event JSON encoding checked via golden fixture)
  - Docs updated: `README.md`, `docs/modules/pi-core-types.md`, `docs/PLAN.md`

## P2 `pi-ai` Migration (Core Dependency)

### P2-1: `pi-ai` foundational types and model registry (minimum closed loop)
- Status: DONE
- Depends On: P1-3
- Scope:
  - Base provider/model types
  - Minimum model lookup/parsing capability
- Test Plan:
  - Model lookup, error-path, and fuzzy-match rule tests
- Verification:
  - Tests: `swift test` passed (22 tests total, including `PiAIModelRegistryTests`) on 2026-02-22
  - Build: `swift build` passed on 2026-02-22
  - Regression: N/A (new `PiAI` registry baseline; edge/error paths covered in unit tests)
  - Docs updated: `README.md`, `docs/modules/pi-ai.md`, `docs/PLAN.md`

### P2-2: Unified message context and stream event model
- Status: DONE
- Depends On: P2-1
- Scope:
  - Context/messages/tool call/result/thinking event structures
- Test Plan:
  - Event sequence serialization/deserialization tests
  - Boundary-field tests
- Verification:
  - Tests: `swift test` passed (24 tests total, including `PiAITypesTests`) on 2026-02-22
  - Build: `swift build` passed on 2026-02-22
  - Regression: N/A (new type-model surface; stable event JSON encoding checked via golden fixture)
  - Docs updated: `README.md`, `docs/modules/pi-ai.md`, `docs/PLAN.md`

### P2-3: JSON / event-stream / validation utility functions
- Status: DONE
- Depends On: P2-2
- Scope:
  - Stream parsing, partial JSON, validation helpers, overflow handling
- Test Plan:
  - Match equivalent `pi-mono` edge cases
- Verification:
  - Tests: `swift test` passed (28 tests total, including `PiAIUtilitiesTests`) on 2026-02-22
  - Build: `swift build` passed on 2026-02-22
  - Regression: Utility edge cases covered for chunked SSE parsing, partial JSON recovery, tool validation, and overflow detection
  - Docs updated: `README.md`, `docs/modules/pi-ai.md`, `docs/PLAN.md`

### P2-4: OpenAI Responses adapter (first provider)
- Status: DONE
- Depends On: P2-2, P2-3
- Scope:
  - First provider adapter with working tool calling and streaming text
- Test Plan:
  - Mock provider tests
  - Event-stream ordering tests
- Verification:
  - Tests: `swift test` passed (30 tests total, including `PiAIOpenAIResponsesProviderTests`) on 2026-02-22
  - Build: `swift build` passed on 2026-02-22
  - Regression: Mock-driven event-order and terminal error behavior validated for streaming text + tool call lifecycle
  - Docs updated: `README.md`, `docs/modules/pi-ai.md`, `docs/PLAN.md`

### P2-5: Anthropic adapter
- Status: TODO
- Depends On: P2-4
- Scope:
  - Message/tool/thinking mapping
- Test Plan:
  - Regression tests for tool-name and argument normalization

### P2-6: Google/Vertex family adapters
- Status: TODO
- Depends On: P2-4
- Scope:
  - Google/Gemini/Vertex message and event handling
- Test Plan:
  - Regression tests for missing-arg tool calls, empty streams, thinking signature, etc.

### P2-7: OAuth and provider credential helpers
- Status: TODO
- Depends On: P2-4
- Scope:
  - OAuth helper abstractions and token injection mechanism
- Test Plan:
  - Token lifecycle and error-path tests

### P2-8: `pi-ai` regression test completion and coverage push
- Status: TODO
- Depends On: P2-5, P2-6, P2-7
- Scope:
  - Align critical behaviors with `../pi-mono/packages/ai/test`
  - Push coverage as close to 100% as practical
- Test Plan:
  - Full module test run
  - Coverage report

## P3 `pi-agent-core` Migration

### P3-1: AgentState / AgentMessage / AgentEvent types
- Status: TODO
- Depends On: P2-2
- Scope:
  - Migrate state model and event types
- Test Plan:
  - Type behavior and state initialization tests

### P3-2: Agent loop (single turn)
- Status: TODO
- Depends On: P3-1, P2-4
- Scope:
  - Single prompt -> streaming assistant message
- Test Plan:
  - Event ordering tests

### P3-3: Tool execution loop (multi-turn)
- Status: TODO
- Depends On: P3-2
- Scope:
  - Execute tool calls, inject tool results, continue next turns
- Test Plan:
  - Multi-turn event sequence and pending-tool-call tests

### P3-4: continue/retry/abort/sessionId/thinkingBudgets
- Status: TODO
- Depends On: P3-3
- Scope:
  - Complete runtime control capabilities
- Test Plan:
  - Abort, continue, and retry-limit tests

### P3-5: `pi-agent-core` regression test completion
- Status: TODO
- Depends On: P3-4
- Scope:
  - Align with `../pi-mono/packages/agent/test`
- Test Plan:
  - Full module test run + coverage

## P4 `pi-tui` Migration

### P4-1: Terminal abstraction + render buffer + differential rendering
- Status: TODO
- Depends On: P1-2
- Scope:
  - Core TUI render loop
- Test Plan:
  - Differential-render and overwrite regression tests

### P4-2: Input/editor/key system
- Status: TODO
- Depends On: P4-1
- Scope:
  - Input/Editor/keys/undo/kill-ring
- Test Plan:
  - Keyboard editing behavior tests

### P4-3: List/Overlay/layout components
- Status: TODO
- Depends On: P4-1
- Scope:
  - `SelectList` / `SettingsList` / overlay options
- Test Plan:
  - Overlay positioning and visibility tests

### P4-4: Markdown/images/autocomplete
- Status: TODO
- Depends On: P4-1
- Scope:
  - Markdown rendering, terminal images, autocomplete
- Test Plan:
  - Markdown wrapping, image protocol, path autocomplete tests

### P4-5: `pi-tui` regression test completion
- Status: TODO
- Depends On: P4-2, P4-3, P4-4
- Scope:
  - Align with `../pi-mono/packages/tui/test`
- Test Plan:
  - Full module test run + coverage

## P5 `pi-coding-agent` Migration (Core Product)

### P5-1: CLI args/help and minimum startup flow
- Status: TODO
- Depends On: P3-5, P4-5
- Scope:
  - Args parser, help, entry `main`, minimum mode-selection loop
- Test Plan:
  - Args/help unit tests and smoke test

### P5-2: Built-in tool protocol and core tools (`read`/`write`/`edit`/`bash`)
- Status: TODO
- Depends On: P5-1, P3-5
- Scope:
  - Tool registration/dispatch; first make the four core tools work end-to-end
- Test Plan:
  - Tool behavior comparison tests
  - Error-path tests

### P5-3: Session management (`save`/`resume`/`continue`)
- Status: TODO
- Depends On: P5-1
- Scope:
  - Session storage/load and basic resume selection capability
- Test Plan:
  - File operations, timestamps, migration tests

### P5-4: Session tree / branching / traversal
- Status: TODO
- Depends On: P5-3
- Scope:
  - Branching session tree and navigation
- Test Plan:
  - Branching/tree traversal regression tests

### P5-5: Compaction (including auto-compaction queue)
- Status: TODO
- Depends On: P5-3, P3-5
- Scope:
  - Compaction flow, strategy, and auto-trigger queue
- Test Plan:
  - Compaction fixtures and regression tests

### P5-6: Skills / Prompt Templates / Themes / Extensions discovery and loading
- Status: TODO
- Depends On: P5-1
- Scope:
  - Resource discovery, frontmatter parsing, conflict handling, validation rules
- Test Plan:
  - Fixture-driven regression tests (skill collisions, invalid frontmatter, etc.)

### P5-7: Settings / Auth Storage / Model Registry & Resolver
- Status: TODO
- Depends On: P5-1, P2-8
- Scope:
  - Settings, credentials, model parsing and resolution logic
- Test Plan:
  - Settings/auth/model resolver regression tests

### P5-8: Interactive TUI mode and key interactions (status bar, selectors, shortcuts)
- Status: TODO
- Depends On: P5-3, P5-6, P4-5
- Scope:
  - Core interactive UI flows
- Test Plan:
  - Interactive state and rendering behavior tests

### P5-9: RPC / JSON / Print / SDK modes
- Status: TODO
- Depends On: P5-1, P5-2, P5-3
- Scope:
  - Non-interactive modes and programmatic integration capability
- Test Plan:
  - Mode output and protocol tests

### P5-10: Attachment/image processing/export capabilities
- Status: TODO
- Depends On: P5-2, P5-8
- Scope:
  - File arguments, image processing, exports (HTML, etc.)
- Test Plan:
  - Attachment and image-processing regression tests

### P5-11: `pi-coding-agent` regression test completion and coverage push
- Status: TODO
- Depends On: P5-4, P5-5, P5-6, P5-7, P5-8, P5-9, P5-10
- Scope:
  - Align critical behaviors with `../pi-mono/packages/coding-agent/test`
- Test Plan:
  - Full module test run + coverage

## P6 Peripheral Capabilities (Incremental by dependency/platform)

### P6-1: `pi-web-ui` feature mapping and Swift platform-equivalent design
- Status: TODO
- Depends On: P2-8, P3-5
- Scope:
  - Define how Web Components functionality maps to Swift surfaces (SwiftUI/WebView/client apps)
- Test Plan:
  - Design review and sample validation

### P6-2: `pi-mom` (Slack bot) migration
- Status: TODO
- Depends On: P3-5, P5-11
- Scope:
  - Slack integration, tool delegation, sandbox abstraction
- Test Plan:
  - Mock Slack event and command-execution tests

### P6-3: `pods` (GPU pod CLI) migration
- Status: TODO
- Depends On: P3-5
- Scope:
  - CLI, SSH, model lifecycle, configuration management
- Test Plan:
  - Config and command-generation tests, integration smoke test

## 6. Documentation Sync Tasks (Continuous)

After any task is completed, append/update the corresponding module doc (recommended):

- `docs/modules/pi-ai.md`
- `docs/modules/pi-agent-core.md`
- `docs/modules/pi-tui.md`
- `docs/modules/pi-coding-agent.md`
- `docs/modules/pi-web-ui.md`
- `docs/modules/pi-mom.md`
- `docs/modules/pi-pods.md`

These docs should include at least:

- Implemented functionality
- Parity status vs `pi-mono`
- Known differences (if any)
- Test coverage and regression points

## 7. Current Entry Point (Next Step)

Next recommended task: `P2-5` (Anthropic adapter). Continue following the strict test-first implementation cadence and atomic-commit rule.
