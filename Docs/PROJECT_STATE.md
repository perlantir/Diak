# Diak — Project State

This is the live source-of-truth document for Diak's current state. Update it
when phases advance or architectural decisions change. Agents read this on
every run but never write to it.

Last human-authored update: 2026-05-11 (post Phase 0 merge, CLAUDE.md scope-doc carve-out added)

## Current Active Phase

**Phase 0.5: Hermes Reality Doc**

Phase 0 is complete and merged to main at SHA `2185e7f`. All 9 acceptance
criteria passed (criterion 8 was ratified after surfacing
`HermesAPIEndpointConfig.swift` as in-scope refactor-by-extraction). See
`Docs/Phases/Phase0/CHECKPOINTS/20260511T135332Z-phase-0-complete.md`.

The next work unit is producing `Docs/Phases/Phase1/REALITY.md` by direct
observation of the real Hermes CLI on this machine. No code changes in this
phase. The Reality Doc is a hard gate before Phase 1.

Phase branch: `phase/0.5-reality-doc` (to be created from main)

## Phase 0 Status

COMPLETE and merged to main at SHA `2185e7f` on 2026-05-11. All 9 acceptance
criteria passed. See checkpoint:
`Docs/Phases/Phase0/CHECKPOINTS/20260511T135332Z-phase-0-complete.md`.

Calibration note from Phase 0: refactor-by-extraction files that organize
in-scope functionality differently are considered in-scope. New files that
introduce new behavior (new endpoints, new dependencies, new types not
implied by scope) require human approval before being added.

## Repository State

- Main branch: at SHA `911c957` (M9 baseline, "Implement M9 beta hardening")
- Origin main: at SHA `911c957` (matches local main)
- Active phase branch: `phase/0-foundation-reset` (in progress, 4 commits ahead
  of main)
- Archive branches preserved (never modify):
  - `archive/pre-reset-full-snapshot`
  - `archive/pre-reset-wip`
  - `archive/phase3-canvas-and-chat`
  - `archive/phase4-connectors-skills-secrets`
  - `archive/phase5-automations-memory`
  - `archive/phase8-uat-harness`
  - `archive/bridge-experiment`

## Locked Architectural Decisions

These are ratified. Do not relitigate without explicit Nick approval.

1. App Sandbox: OFF. Distributed via Developer ID + notarization, not Mac App
   Store.
2. Hardened Runtime: ON, with `cs.allow-jit`, `cs.disable-library-validation`,
   `cs.allow-unsigned-executable-memory`.
3. Hermes runs bundled inside `Diak.app/Contents/Resources/hermes-runtime/`.
   Diak owns its lifecycle.
4. Hermes data lives at `~/Library/Application Support/Diak/hermes/`.
5. Daemon endpoint: TO BE DETERMINED by Phase 1 reality doc. Default assumed
   `http://127.0.0.1:8765` until proven otherwise.
6. Auth mechanism: TO BE DETERMINED by Phase 1 reality doc.
7. URL scheme: `diak` registered in `Info.plist`. OAuth callbacks land at
   `diak://oauth-callback`.
8. Single source of truth: the daemon (or bridge adapter, pending Phase 1
   decision). App holds a cached projection in `HermesState`.
9. State container: `HermesState` is a `@MainActor ObservableObject` exposed
   via `@EnvironmentObject`.
10. Project generation: via XcodeGen from `project.yml`. Do not hand-edit the
    generated `.xcodeproj`.
11. Working tool for this project: Claude Code, invoked from the repo root.
    The Hermes agent is not used for Diak development going forward.
12. Phase 0 verification model: every phase ends with a checkpoint that
    records each acceptance criterion as PASS/FAIL with supporting evidence.
    Nick reviews the checkpoint and performs the merge to main manually.
    The agent does not merge.

## The Phase 0–8 Roadmap

### Phase 0: Architectural Reset (in progress)
Foundation work that does not depend on Hermes' actual contract. Sandbox off,
URL scheme, AppDelegate, HermesState scaffold, API client cleanups.

### Phase 0.5: Hermes Reality Doc (gate between Phase 0 and Phase 1)
Document what real Hermes actually exposes by direct observation. No code.
Human-ratified before Phase 1 begins.

### Phase 1: Hermes Runtime Bundling + Process Supervision
Bundled Hermes binary, fetch script, `HermesProcessSupervisor`, auth token
machinery, URLSessionHermesAPIClient wired to real Hermes endpoints, restart
button actually works. Six real-Mac acceptance scenarios.

### Phase 2: Real-Time Event Stream
Replace polling with SSE (or polling fallback if Hermes doesn't emit SSE).
`HermesState` becomes reactive. Acceptance: state changes propagate to UI
within 2 seconds.

### Phase 3: Chat plus Canvas
Real streaming markdown rendering, tool-call cards, approval flow round-trip,
right-side inspector showing live activity and artifacts.

### Phase 4: Skills, Connectors, OAuth
OAuth round-trip via system browser and URL scheme callback, Composio
connector setup, skill install/enable/disable, Keychain-backed secrets.

### Phase 5: Automations and Memory
Conversational automation builder, scheduled execution, autonomous safety
gates, memory dashboard with edit/delete.

### Phase 6: Native Mac Polish
Real notifications, global hotkey, menu bar polish, drag-and-drop, window
restoration, accessibility audit.

### Phase 7: Distribution, Updates, Telemetry
Developer ID signing, notarization, Sparkle auto-updates, opt-in Sentry, real
DMG distribution.

### Phase 8: Hardening for Ship
Sleep/wake, multi-monitor, network resilience, performance budgets, strict
concurrency, beta with real users.

## What the Agent Is Allowed to Do Right Now

- Read `CLAUDE.md`, this file, and `Docs/Phases/Phase1/REALITY-SCOPE.md`.
- Create branch `phase/0.5-reality-doc` from current main.
- Produce `Docs/Phases/Phase1/REALITY.md` by direct observation of the
  Hermes CLI installed on this machine.
- Write checkpoints to `Docs/Phases/Phase1/CHECKPOINTS/`.
- Push to `phase/0.5-reality-doc` branch only.

## What the Agent Is Not Allowed to Do Right Now

- Modify any Swift file. Phase 0.5 is investigation and documentation only.
- Modify anything outside `Docs/Phases/Phase1/`.
- Make Path A vs Path B (Python bridge vs direct integration) decisions —
  Nick decides after reviewing the Reality Doc.
- Begin any Phase 1 implementation work.

## Known Issues (Deferred)

These were observed during Phase 0 verification but are not Phase 0 issues.
Address in a later phase.

- Three stale `Diak.app` bundles register the `diak://` URL scheme with
  LaunchServices (two in `/private/tmp/diak_phase1_e2e_*`, one in stale
  DerivedData). May cause macOS to route `diak://` URLs to wrong builds.
  Clean up before public distribution.
- `zsh` builtin `log` shadows `/usr/bin/log`. Future automation that calls
  `log show` should use the absolute path.

## Human Contact

Project owner: Nick. All non-trivial decisions wait for Nick approval via
checkpoint review.
