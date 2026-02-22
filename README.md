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

Project bootstrapping and planning docs are in place. Implementation starts with Swift project/module scaffolding (`P1-1` in `docs/PLAN.md`).
