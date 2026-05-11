# Diak — Project State

This is the live source-of-truth document for Diak's current state. Update it
when phases advance or architectural decisions change. Agents read this on
every run but never write to it.

Last human-authored update: 2026-05-11

## Current Active Phase

**Phase 0: Architectural Reset**

Phase 0 work is complete on the `phase/0-foundation-reset` branch but has not
yet been verified against this `SCOPE.md` system or merged to main.

The next work unit is: verify Phase 0 against `Docs/Phases/Phase0/SCOPE.md`
acceptance criteria, write a retroactive completion checkpoint, then merge to
main.

Phase branch: `phase/0-foundation-reset`

## Phase 0 Commits Already on Branch

- 5c475e1 chore: update Phase 0 entitlements and URL scheme
- 9cd9c23 chore: add Phase 0 app state and lifecycle scaffolding
- af94bec chore: shape Phase 0 deep-link route type
- 5421ac8 refactor: consolidate Hermes API client foundation

These commits were created under prior process rules. They need to be verified
against the current `Docs/Phases/Phase0/SCOPE.md` before merging.

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

- Read this file, CLAUDE.md, and `Docs/Phases/Phase0/SCOPE.md`.
- Verify the four existing Phase 0 commits against the acceptance criteria in
  `Docs/Phases/Phase0/SCOPE.md`.
- Write a retroactive completion checkpoint at
  `Docs/Phases/Phase0/CHECKPOINTS/<timestamp>-phase-0-complete.md` if
  verification passes.
- Push to the `phase/0-foundation-reset` branch.

## What the Agent Is Not Allowed to Do Right Now

- Modify any Swift file. Phase 0 work is already complete; this is verification
  only.
- Start the Reality Doc (Phase 0.5) or Phase 1 work.
- Modify `CLAUDE.md` or this file.
- Merge `phase/0-foundation-reset` to main. The human will do the merge after
  reviewing the verification checkpoint.

## Human Contact

Project owner: Nick. All non-trivial decisions wait for Nick approval via
checkpoint review.
