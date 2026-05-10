# Claude Code M10 Phase 2 Canvas Artifacts Kickoff

You are working in `/Users/perlantir/Projects/HermesDesktop`, the Diak SwiftUI macOS app. Follow `CLAUDE.md` and keep the product boundary: SwiftUI owns the Mac UI/state/API boundary; Hermes Agent remains the engine/daemon. Do **not** reimplement Hermes internals, model/tool dispatch, browser execution, code execution, or connector writes inside the app.

## Current state

M0–M9 are implemented and locally verified. M10 Phase 1 is implemented: Chat + Canvas UI/state, model override routing for automations, and a first real daemon SSE boundary via `URLSessionHermesAPIClient.streamEvents(sessionID:)`.

Fresh local verification immediately before this prompt:

```bash
xcodegen generate
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test   # 137 tests, 0 failures
Scripts/m9_release_gate.sh                                           # PASS, report build/m9/M9_RELEASE_GATE_20260510-090601.md
git diff --check                                                     # PASS
```

The repo is on `main`, clean before this prompt, and ahead of origin locally. Do not push.

## Source docs

- `Docs/Plans/M10_CHAT_CANVAS_MODEL_ROUTING.md`
- `Docs/HERMES_DESKTOP_FULL_BUILD_SPEC.md`
- `Docs/DESIGN_PACKAGE_REVIEW_AND_BUILD_HANDOFF.md`
- `CLAUDE.md`

## Scope: M10 Phase 2 — persisted canvas artifacts/documents boundary only

Implement the smallest production-quality slice for persisted canvas artifacts/documents per session. This is a typed UI/API-boundary slice, not real Hermes runtime execution.

Acceptance criteria:

1. Add typed models for session canvas artifact/document references if missing, reusing `HermesArtifactRef` where appropriate instead of duplicating concepts.
2. Add API client protocol methods and URLSession endpoints for reading persisted canvas artifacts/documents for a session. Use a conservative local-daemon path such as `GET /sessions/{id}/canvas/artifacts` and document/centralize it in the URL client. Decode snake_case tolerantly and handle unknown artifact kinds safely.
3. Add mock client persistence/fixtures for canvas artifacts per session so previews/tests can show document/code/browser/design artifacts without live daemon execution.
4. Wire `ChatViewModel`/canvas state so selecting/opening a session can load persisted artifacts and reflect them in the Canvas tabs/activity/document sections without hardcoded screenshot-only content.
5. Add user-safe error/empty states for artifact loading. Do not block chat streaming if artifact loading fails.
6. Add tests for:
   - artifact/document model decoding and unknown/tolerant cases;
   - URLSession endpoint path/method/decoding;
   - mock client session-scoped persistence;
   - `ChatViewModel` loading artifacts into canvas state and surfacing non-blocking load failures.
7. Keep all external/runtime execution marked NOT TESTED. Do not add production writes, connector writes, shell execution, or browser automation inside the app.

## Out of scope

- Production Hermes daemon implementation.
- Real browser/code/design preview execution.
- Developer ID signing/notarization/Gatekeeper changes.
- Connector writes or unsafe actions.
- Cron/job modification.
- Broad refactors or rebranding.

## Required verification before stopping

Run these from the repo root and include exact results in your final response:

```bash
xcodegen generate
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git diff --check
```

If the direct build/tests are green and time remains, also run:

```bash
Scripts/m9_release_gate.sh
```

Leave changes uncommitted for Hermes to inspect. Do not push. Do not modify cron jobs. Keep scope tight to M10 Phase 2 canvas artifact persistence/API boundary.
