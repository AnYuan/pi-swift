# PiMom Module Progress

## Scope

This document tracks `PiMom` migration progress and parity status against `../pi-mono/packages/mom` (Slack bot + sandboxed command execution + persistent workspace orchestration).

## `P6-2` Progress (Sandbox Abstraction Foundation Slice, In Progress)

Files:

- `/Users/anyuan/Development/pi-swift/Sources/PiMom/Sandbox.swift`
- `/Users/anyuan/Development/pi-swift/Tests/PiMomTests/PiMomSandboxTests.swift`

Implemented in this slice:

- sandbox config parsing parity foundation
  - `host`
  - `docker:<container>`
  - structured parse errors for invalid sandbox type / missing docker container name
- sandbox execution abstraction
  - `PiMomExecutor` protocol
  - `PiMomHostExecutor`
  - `PiMomDockerExecutor`
  - `PiMomExecutorFactory`
- process runner abstraction for testability
  - `PiMomProcessRunning`
  - `PiMomDefaultProcessRunner` (Process-based)
- Docker command wrapping semantics
  - wraps commands with `docker exec <container> sh -c ...`
  - shell escaping for single quotes
- workspace path translation parity
  - host -> passthrough
  - docker -> `/workspace`

Tests added:

- host/docker sandbox parsing
- parse error paths
- host executor shell invocation shape
- docker executor wrapping + escaping behavior

Verification (slice):

- `swift test --filter PiMomSandboxTests` passed on 2026-02-24

## Notes / Parity Gaps (Pending)

- Slack Socket Mode integration
- channel queue + running/stop orchestration
- event file watcher / scheduler
- workspace log/context store parity
- tool delegation and attach/upload flows
