# pi-swift AGENTS.md

## Project Goal

The primary goal of this repository is to reimplement the TypeScript implementation in `../pi-mono` using Swift while preserving functional behavior.

Core requirements:

- Full feature parity
- No regressions (behavioral regressions)
- Tests are the source of truth for acceptance
- Documentation must be updated together with implementation

`../pi-mono` is the current functional baseline and reference implementation (source of truth).

## Working Principles (Required)

1. Start by checking unfinished tasks in `docs/PLAN.md` and pick one smallest executable task.
2. Write tests first (or create executable acceptance fixtures/golden cases first), then implement.
3. After implementation, run the relevant tests and record verification results.
4. Only update task status after tests pass and compilation passes.
5. For every completed task, update the related module docs under `docs/` (at minimum: changes, behavior, test coverage).
6. Review your own changes before moving to the next task.
7. Commit changes atomically: each commit should represent one coherent, independently reviewable change.

## Task Status Update Rules (Strict)

- Do not update a task to completed before verification passes.
- A task can only move to completed when all of the following are true:
  - Relevant tests pass
  - Relevant build/compilation passes
  - Regression checks pass (covering the impacted surface area)
  - Documentation is updated
- If testing cannot be run or the environment is missing, the task must not be marked completed; mark it blocked or pending verification and document the reason.

## Quality Gate (Definition of Done)

A task is considered done only if it satisfies at least:

- Behavior matches the corresponding functionality in `../pi-mono` (inputs/outputs/errors)
- New or updated tests cover core paths and edge cases for the task
- Coverage is as close to 100% as practical (especially core logic)
- Compilation passes (SwiftPM / Xcode target as applicable)
- No obvious code smell, duplicated logic, or unhandled error paths
- Related module docs under `docs/` are updated

## Recommended Execution Loop (Standard Cadence)

1. Read `docs/PRD.md` and `docs/ARCHITECTURE.md` to confirm target behavior and module boundaries.
2. Pick one `TODO` task from `docs/PLAN.md` whose dependencies are satisfied.
3. Review the corresponding module in `../pi-mono` (source, tests, README) and extract acceptance examples.
4. Write Swift tests first (unit tests preferred; integration tests when needed).
5. Implement until tests pass.
6. Run tests and compile checks.
7. Self-review (naming, boundaries, error handling, concurrency, performance, documentation).
8. Update the relevant module docs under `docs/`.
9. Record verification evidence, then update task status in `docs/PLAN.md`.
10. Return to step 2.

## Documentation Conventions

- `docs/PRD.md`: feature inventory, acceptance goals, non-goals, constraints.
- `docs/PLAN.md`: phase breakdown, task list, dependencies, status, verification evidence.
- `docs/ARCHITECTURE.md`: high-level architecture diagram, module mapping, boundaries, dependency relationships.
- Future module docs should live in `docs/modules/<module>.md` (for example, `docs/modules/pi-ai.md`).
- All project documentation must be written in English.

## Implementation Strategy (Current Constraint)

- Prioritize the core capability chain first: `pi-ai` -> `pi-agent-core` -> `pi-tui` -> `pi-coding-agent`
- Then expand to peripheral capabilities such as `mom`, `pods`, and `web-ui`
- If new `pi-mono` features affect already-implemented modules, add regression tests and update PRD/PLAN first

## Prohibited Shortcuts

- Marking a task done without running tests
- Skipping behavior-parity verification just to move faster
- Claiming compatibility without recorded evidence
- Updating task status without documenting verification method/results
- Mixing unrelated changes into a single commit

## Minimum Pre-Completion Checklist (Per Task)

- Relevant tests pass
- Relevant targets compile successfully
- Documentation is updated
- Task status is updated only after verification
