# Claude Code Kickoff — M12 Slice 6 Direct Add Skill UX

You are working in `/Users/perlantir/Projects/HermesDesktop` on Diak, a SwiftUI macOS control-center app for Hermes Agent.

## Non-negotiable product boundary

- Public app surfaces say **Diak**.
- Hermes Agent / Hermes Engine remains the local daemon/API runtime.
- Do **not** reimplement Hermes internals inside the Swift app.
- This slice is UI/state/API-boundary work for the Skills screen only. Do not jump to connectors live writes, billing, Sparkle, unrelated release work, or broad bridge rewrites.

## Source docs

Read/follow:

- `CLAUDE.md`
- `Docs/Plans/M12_IN_APP_SETUP_AND_CORE_UX_FIXES.md` Slice 6
- Current implementation in `HermesDesktop/Features/Skills/`, `HermesDesktop/Services/HermesAPI/`, and tests in `HermesDesktopTests/SkillsViewModelTests.swift`.

## Current state

M12 Slices 1-5 are independently verified and committed locally. Latest commits before this work:

- `25cb9f0 fix: make canvas tabs interactive controls`
- `5d0bfd9 feat: add guided automation setup UX`
- `69aa2c1 fix: harden bridge evidence and metadata boundary`

## Slice 6 scope — Direct Add Skill UX

Files likely involved:

- `HermesDesktop/Features/Skills/SkillsView.swift`
- `HermesDesktop/Features/Skills/SkillsViewModel.swift`
- `HermesDesktopTests/SkillsViewModelTests.swift`
- Only touch typed API/mock/bridge files if a missing direct draft/create contract is necessary.

## Requirements

1. Add a visible **Add Skill** button in the Skills screen.
2. Add a form/sheet/card with fields:
   - name
   - summary
   - trigger
   - category
   - risk style
   - optional instructions/content
3. Submit creates a draft/skill through the typed API boundary.
4. The user must not need an existing chat session to create the draft/skill.
5. Show clear confirmation that Hermes Agent owns install/execution.
6. Validate required fields with user-visible errors before submit.
7. Product copy must not say mock/local/internal milestone labels in production UX except in explicit debug/build notes.
8. Keep view code thin; put draft validation/state transitions in the view model where testable.

## Verification you must run before exiting

Run the broad practical gate:

```bash
python3 -m unittest Tests.diak_hermes_bridge_tests
xcodegen generate
xcodebuild -list
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git diff --check
```

If something fails, fix deterministic issues in this slice. If blocked by an environmental issue, report exact command/output and leave code in the best small state.

## Output

Leave changes uncommitted for Hermes to inspect. In your final JSON/text result, summarize:

- Files changed
- Direct Add Skill UX/state/API-boundary behavior implemented
- Tests added/updated
- Exact verification commands/results
- Risks or remaining follow-up

IMPORTANT: Actually implement M12 Slice 6 now. Make code changes. Do not only analyze or plan.
