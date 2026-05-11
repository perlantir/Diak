# Claude Code Kickoff — M12 Slice 9: App-state UAT seam for form submission proof

You are working in `/Users/perlantir/Projects/HermesDesktop` on Diak, the SwiftUI macOS control center for Hermes Agent.

## Product boundary

- Public app surfaces say **Diak**.
- Hermes Agent / Hermes Engine remains behind the local daemon/API boundary.
- Do not reimplement Hermes internals in Swift.
- Keep this as a small M12 UAT/testability slice only.

## Current state

Recent verified commits:

- `69c8df5 feat: add UAT testability hooks`
- `4bfd944 docs: record M12 slice 7 verification`
- `143ecda test: add full-app UAT harness`
- `3c344ef docs: record M12 slice 8 UAT evidence`

Slice 8 added `--diak-uat-mode` plus a full-app XCUITest harness for Memory / Skills / Automations. The default generated-project release gate is green, but the actual XCUITest runner is BLOCKED in the unattended cron environment by macOS/Xcode UI-test runner scheme/signing policy. Do not claim actual-app visual PASS from that.

## Your task

Implement the smallest safe app-state UAT seam that gives stronger deterministic PASS evidence for Memory / Skills / Automations form submission behavior without relying on the macOS XCUITest runner.

Preferred route:

1. Add pure Swift app-side testability/state seams that exercise the same form entry and submission reducers/view-model paths used by the visible SwiftUI forms.
2. Add tests proving the full form flow for:
   - Memory: add, fill title/body/scope/pinned/acknowledgement, save, verify visible/list state, edit/delete if safe in mock state.
   - Skills: direct-add required fields + acknowledgement gating, submit, verify created skill row/enabled state through `MockHermesAPIClient`.
   - Automations: create title/prompt/schedule/delivery, test-run, update schedule or delivery, delete, verify mock state.
3. Keep this as real app/view-model state proof, not a fake assertion over constants. Reuse existing view models and `MockHermesAPIClient` where possible.
4. Update status/release docs with an honest distinction:
   - Swift app-state UAT: PASS if your tests pass.
   - Actual visual typed/clicked XCUITest: still BLOCKED/PARTIAL until run in a signed local UI-test session.

## Hard boundaries

- Do not start M13 or unrelated features.
- Do not use real provider credentials or real connector OAuth.
- Do not push, publish, send messages, modify cron jobs, or perform external account side effects.
- Do not commit raw screenshots or raw local catalogs/private skill names.
- Do not claim full actual-app visual PASS unless the built app was launched/clicked/typed and evidence supports it.

## Verification required before you stop

Run and report exact results for:

```bash
xcodegen generate
xcodebuild -list
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
python3 -m unittest Tests.diak_hermes_bridge_tests
python3 qa/uat/memory_skills_automations_uat.py
python3 qa/uat/full_app_xcuitest_uat.py
git diff --check
```

Leave changes uncommitted for Hermes to inspect. Summarize changed files, tests/UAT added, verification output, sanitized evidence paths, and any remaining gap.
