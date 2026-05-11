# Claude Code Kickoff — M12 Slice 7: UAT testability hooks for Memory / Skills / Automations

You are working in `/Users/perlantir/Projects/HermesDesktop` on Diak, the SwiftUI macOS control center for Hermes Agent.

## Product boundary

- Public app surfaces say **Diak**.
- Hermes Agent / Hermes Engine remains behind the local daemon/API boundary.
- Do not reimplement Hermes internals in Swift.
- Keep this as a small M12 hardening slice only.

## Current state

Recent verified commit `10851ac feat: harden memory and automation UAT flows` added:
- manual Memory create UI/view-model flow with acknowledgement gate
- Automation delivery destination create/update flow
- bridge support for automation delivery and paired cron delete
- deterministic UAT API/state harness under `qa/uat/`

Full regenerated-project Swift tests and Python bridge tests passed before this prompt. The remaining release gap is actual SwiftUI form click-through evidence: desktop accessibility automation could launch Diak and probe routes, but could not reliably target every Memory / Skills / Automations form control.

## Your task

Implement the smallest app-side testability slice that makes Memory / Skills / Automations UAT automation reliable without changing product behavior.

Prefer:
1. Stable accessibility identifiers/names for the real Memory create/edit controls, Skills direct-add controls, and Automations create/update/test-run/delete controls.
2. Pure Swift view-model/state seams or helpers that XCTest can assert for selected form mode, required acknowledgement state, delivery target state, and action availability.
3. XCTest coverage that proves those identifiers/state seams stay stable for UAT and do not collide.
4. If useful, update `qa/uat/diak_memory_skills_automations_report.md` to say the next visual UAT runner can target the new identifiers.

## Hard boundaries

- Do **not** start M13 or unrelated features.
- Do **not** add live provider requirements.
- Do **not** perform external side effects, push, publish, send messages, or modify cron jobs.
- Do **not** store secrets or raw API keys.
- Do **not** rewrite the app architecture.
- Do **not** claim full actual-app visual PASS unless you truly automate/click the actual app and collect evidence. If you only add identifiers/tests, mark visual dogfood as still PARTIAL.

## Verification required before you stop

Run and report exact results for:

```bash
xcodegen generate
xcodebuild -list
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
python3 -m unittest Tests.diak_hermes_bridge_tests
python3 qa/uat/memory_skills_automations_uat.py
git diff --check
```

Leave changes uncommitted for Hermes to inspect. Summarize changed files, tests added, verification output, and any remaining gap.
