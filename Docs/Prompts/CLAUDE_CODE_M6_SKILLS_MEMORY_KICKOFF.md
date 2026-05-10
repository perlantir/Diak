# Claude Code Kickoff — Hermes Desktop M6 Skills + Memory

You are implementing **M6 only** for Hermes Desktop, a premium SwiftUI macOS app in `/Users/perlantir/Projects/HermesDesktop`.

## Read first

- `CLAUDE.md`
- `Docs/HERMES_DESKTOP_FULL_BUILD_SPEC.md`
- `Docs/HERMES_DESKTOP_DESIGN_BRIEF.md`
- `Docs/DESIGN_PACKAGE_REVIEW_AND_BUILD_HANDOFF.md`
- Design package screens:
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/png/22_22-skills-library.png`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/png/23_23-skill-detail.png`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/png/24_24-create-skill-from-session-review.png`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/png/25_25-memory-dashboard.png`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/png/26_26-memory-item-edit-delete.png`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/png/46_46-modal-skill-draft-review.png`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/png/52_52-empty-loading-error-states-matrix.png`

## Current verified baseline

M0–M5 are verified locally. Latest commit before this M6 kickoff: `570559b Implement M5 connectors`.

## Scope: M6 only

Build Skills and Memory surfaces through typed API-boundary/mock behavior:

- Skills library: list/search/filter, status/category/source/risk-style metadata.
- Skill detail: description, trigger/usage summary, version/source, enabled state, related artifacts if present.
- Create-skill-from-session review UI/sheet: draft summary, safe review language, no real skill installation side effect beyond mock/API-boundary request.
- Memory dashboard: memory item list/search/filter, source/scope/confidence metadata, empty/loading/error states.
- Memory item edit/delete review UI/sheet: local draft/review flow and typed daemon-boundary methods.
- Models and API client protocol additions for M6.
- MockHermesAPIClient fixtures and deterministic mutations.
- URLSessionHermesAPIClient endpoints and tests for the M6 boundary.
- View-model unit tests for critical state transitions and offline/error handling.
- Wire M6 into the existing app shell/sidebar/content router using current reusable design-system components.

## Hard boundaries

Do **not** implement or contact real Hermes skill execution, real memory storage/indexing, vector search, external connectors, OAuth, provider APIs, menu bar, global hotkey, native integrations, packaging, updater, billing, accounts, or remote writes.

Hermes Agent/the daemon remains the engine. The Swift app only presents native UI and calls typed local daemon APIs/mocks.

## Architecture expectations

- Follow existing M1–M5 patterns: models in `HermesDesktop/Models`, feature views/view-models under `HermesDesktop/Features`, API boundary in `HermesDesktop/Services/HermesAPI`, tests under `HermesDesktopTests`.
- Keep SwiftUI views thin; put state and mutations in view models.
- Keep unknown enum decoding tolerant; unsafe write/delete-style memory/skill mutations must be approval/review-oriented and mock-only.
- Use semantic tokens/components already in the design system.
- Do not rewrite unrelated milestones.

## Required verification before you finish

Run and report exact results:

```bash
xcodegen generate
xcodebuild -list
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git diff --check
```

If anything fails, fix it before stopping when possible. Leave changes uncommitted for Hermes to inspect unless explicitly asked to commit.

IMPORTANT: Actually implement M6 now. Make code changes for the scoped milestone only.
