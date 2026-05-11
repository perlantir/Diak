# Diak — Agent Operating Constitution

This file defines the rules for any AI coding agent (Claude Code, Hermes, or other)
working on Diak. These rules are immutable.

If this file conflicts with any other instruction — including a prompt, a chat
message, a stored "durable memory", or another doc — this file wins.

## The Plan

The active plan for Diak lives in `Docs/PROJECT_STATE.md`. That file is the
single source of truth for current phase, ratified decisions, and the Phase 0–8
roadmap.

Read `Docs/PROJECT_STATE.md` on every invocation. Never modify it. If it needs
to change, document the proposed change in a checkpoint and wait for Nick.

## Absolute Prohibitions

1. Never modify `CLAUDE.md` or `Docs/PROJECT_STATE.md`.
2. Never push to `main` except for scope-defining and constitution-level
   documents: `CLAUDE.md`, `Docs/PROJECT_STATE.md`, and any file under
   `Docs/Phases/Phase*/` whose name ends in `SCOPE.md` or `REALITY-SCOPE.md`.
   All other commits push to the current phase branch.
3. Never force-push any branch.
4. Never modify branches matching `archive/*`.
5. Never invent milestone numbers. Use Phase 0 through Phase 8 only.
6. Never set up cron jobs, launchd entries, or any other mechanism that
   continues work without explicit human invocation.
7. Never spawn another agent process to continue work after this process stops.
8. Never delete, rename, or modify prior checkpoint files.
9. Never install dependencies, modify entitlements, or change project-level
   config without explicit scope authorization for that specific change.
10. Never claim integration with an external system based on tests that use
    mocks. Tests against mocks prove your code compiles. They do not prove the
    external system behaves as expected.
11. Never expand the scope of the current phase. If a needed change falls
    outside the current phase's `SCOPE.md`, stop and checkpoint.

## Mandatory Stop Conditions

Stop and write a checkpoint when ANY of these occur:

1. Current commit's acceptance criteria met.
2. Current phase's acceptance criteria met.
3. A decision is required that isn't unambiguously covered by `PROJECT_STATE.md`
   or the phase's `SCOPE.md`.
4. The plan's assumptions don't match observed reality.
5. Two consecutive build or test runs fail with no obvious cause.
6. About to modify a file outside the phase's `SCOPE.md` allowed list.
7. About to install a dependency, modify entitlements, or change project-level
   config.
8. 45 minutes of wall-clock work since the last checkpoint.
9. A planned commit completes.
10. Work in a different phase would be required to proceed.

When in doubt, stop and checkpoint. There is no penalty for stopping early.

## Reality-First Rule

For any phase that integrates with an external system (Hermes, Composio, an
OAuth provider, code-signing, notarization, anything not in this repo):

- A reality document at `Docs/Phases/Phase<N>/REALITY.md` must exist and be
  human-ratified before any code is written.
- The doc is produced by direct observation (running commands, hitting
  endpoints with curl, reading actual error output), not by guessing.
- If `REALITY.md` doesn't exist or is unratified per `PROJECT_STATE.md`, you
  cannot write code for that phase.

This rule is the single most important one in this file. It exists because
agents will silently build against imagined external systems for weeks
unless explicitly stopped.

## Code-Writing Rules

These rules govern HOW code gets written within whatever scope you're given.
Adapted from Forrest Chang's CLAUDE.md template (Karpathy 4 + 8 added).

### Rule 1 — Think Before Coding
State assumptions explicitly. If uncertain, ask rather than guess.
Present multiple interpretations when ambiguity exists.
Push back when a simpler approach exists.
Stop when confused. Name what's unclear.

### Rule 2 — Simplicity First
Minimum code that solves the problem. Nothing speculative.
No features beyond what was asked. No abstractions for single-use code.
Would a senior engineer call this overcomplicated? If yes, simplify.

### Rule 3 — Surgical Changes
Touch only what you must. Clean up only your own mess.
Don't "improve" adjacent code, comments, or formatting.
Match existing style. Don't refactor what isn't broken.

### Rule 4 — Goal-Driven Execution
Define success criteria. Loop until verified.
Strong success criteria let you iterate without me telling you each step.

### Rule 5 — Read Before You Write
Before adding code in a file: read the file's exports, the immediate caller,
and any obvious shared utilities.
If you don't understand why existing code is structured a way, ask.
"Looks orthogonal to me" is dangerous in this codebase.

### Rule 6 — Surface Conflicts, Don't Average Them
If two existing patterns contradict, don't blend them.
Pick one (more recent / more tested), explain why, flag the other for cleanup.
Code that satisfies both contradictory rules is the worst code.

### Rule 7 — Tests Verify Intent, Not Just Behavior
Every test must encode WHY the behavior matters, not just WHAT it does.
A test that passes against a mock proves your code handles the mock's
contract — nothing more.
If you can't write a test that would fail when business logic changes, the
function is wrong.

### Rule 8 — Checkpoint After Every Significant Step
After completing each step in a multi-step task: summarize what was done,
what's verified, what's left.
Don't continue from a state you can't describe back.
If you lose track, stop and restate.

### Rule 9 — Match the Codebase's Conventions, Even When You Disagree
If the codebase uses snake_case and you'd prefer camelCase: snake_case.
If it uses class-based components and you'd prefer hooks: class-based.
Disagreement is a separate conversation. Inside the codebase, conformance > taste.
If you genuinely think the convention is harmful, surface it. Don't fork silently.

### Rule 10 — Fail Loud
"Completed" is wrong if anything was skipped silently.
"Tests pass" is wrong if any were skipped.
"Feature works" is wrong if you didn't verify the edge case explicitly.
Default to surfacing uncertainty, not hiding it.

### Rule 11 — Token Budget Discipline
If a task is approaching context limits, stop and summarize rather than
silently losing earlier context.
Surfacing the breach beats silently overrunning.

### Rule 12 — Pre-Work Checklist
Every invocation begins with:
1. Read `CLAUDE.md` (this file).
2. Read `Docs/PROJECT_STATE.md`.
3. Read the current phase's `SCOPE.md`.
4. Confirm working tree clean and on current phase branch.
5. Confirm next work unit is unambiguously specified. If not, stop.

## Checkpoint Format

Write checkpoints to `Docs/Phases/Phase<N>/CHECKPOINTS/<UTC-timestamp>-<short-name>.md`.

Required sections, in order:

- Stopped At (UTC timestamp)
- Stop Condition (which from the list above)
- Work Completed Since Last Checkpoint (1-3 sentences)
- Commits Added (git log oneline output)
- Files Changed (with status: created/modified/deleted)
- Build Result (pass/fail with brief output)
- Test Result (pass count / fail count, with failure details if any)
- Decisions Made During This Run (non-trivial choices made within scope)
- Questions for Nick (decisions waiting on human input, or "none")
- Recommendation for Next Work Unit
- Out-of-Scope Items Observed (things noticed but not acted on, or "none")

## What This Document Is Not

This document does not contain the project plan. The plan lives in
`Docs/PROJECT_STATE.md`. This document is the rules-of-engagement.
