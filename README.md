# pi-swift

Swift reimplementation of the TypeScript-based [`pi-mono`](../pi-mono) project, built with a strict parity-first migration strategy.

## Project Goal

This repository aims to recreate the core functionality of `pi-mono` in Swift while preserving behavior and avoiding regressions.

Key goals:

- Feature parity with `../pi-mono`
- Regression-safe migration through tests
- Incremental delivery by phases
- Documentation-driven implementation (PRD, architecture, plan)

## Migration Principles

- Behavior parity over line-by-line translation
- Test-first implementation for each task
- Update task status only after tests + build + docs are complete
- Keep module docs in sync with code changes
- Use atomic commits (one coherent change per commit)

## Current Workflow

1. Pick one unfinished task from `docs/PLAN.md`
2. Read the corresponding `pi-mono` source/tests
3. Write tests (or parity fixtures) first
4. Implement in Swift
5. Run tests and compile checks
6. Update docs
7. Only then mark the task as done

## Documentation

- PRD: `docs/PRD.md`
- Architecture: `docs/ARCHITECTURE.md`
- Execution Plan: `docs/PLAN.md`
- Project rules: `AGENTS.md`

## Scope (Initial Priority)

The migration is planned in dependency order:

1. `pi-ai`
2. `pi-agent-core`
3. `pi-tui`
4. `pi-coding-agent`
5. Peripheral modules (`mom`, `pods`, `web-ui`)

## Status

Project bootstrapping/planning docs are in place, and `P1` groundwork is underway:

- `P1-1` SwiftPM/module skeleton: implemented and verified
- `P1-2` shared test infrastructure (fixtures/goldens): implemented and verified
- `P1-3` cross-module foundational core types: implemented and verified

`P2` has started:

- `P2-1` `pi-ai` foundational model registry: implemented and verified
- `P2-2` `pi-ai` unified context/message/event types: implemented and verified
- `P2-3` `pi-ai` utility foundations (SSE parsing, JSON parsing, validation, overflow detection): implemented and verified
- `P2-4` first provider adapter (`OpenAI Responses`, mock-driven event processor): implemented and verified
- `P2-5` Anthropic adapter (mock-driven thinking/text/tool mapping + OAuth tool-name normalization regression tests): implemented and verified
- `P2-6` Google/Vertex family adapter core (mock-driven Google stream mapping + thinking signature / empty-stream / missing-args regression tests): implemented and verified
- `P2-7` OAuth and provider credential helpers (registry, expiry-aware refresh, API key injection): implemented and verified
- `P2-8` `pi-ai` regression/coverage push: implemented and verified (`docs/reports/pi-ai-coverage.md`)

`P3` has started:

- `P3-1` `pi-agent-core` state/message/event foundational types: implemented and verified
- `P3-2` `pi-agent-core` single-turn agent loop (streamed assistant event -> agent event sequence): implemented and verified
- `P3-3` `pi-agent-core` multi-turn tool execution loop (tool-call execution, tool-result injection, next-turn replay): implemented and verified
- `P3-4` `pi-agent-core` runtime controls (continue/retry entrypoint, steering/follow-up loops, abort controller, request-options plumbing): implemented and verified
- `P3-5` `pi-agent-core` regression test completion + coverage report: implemented and verified (`/Users/anyuan/Development/pi-swift/docs/reports/pi-agent-core-coverage.md`)

Next step: `P6-1` (`pi-web-ui` feature mapping and Swift platform-equivalent design) in `/Users/anyuan/Development/pi-swift/docs/PLAN.md`.
