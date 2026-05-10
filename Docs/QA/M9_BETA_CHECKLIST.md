# M9 Beta Checklist — Diak

Updated: 2026-05-10

## Scope

M9 is the beta-hardening gate after M8. It does **not** mean every future feature is complete. It means the current Diak app is ready for controlled internal dogfood/private beta only when the checks below are classified honestly.

## Verdict states

- **PASS** — verified with evidence.
- **PARTIAL** — safe subset works, but a live/product path remains unproven.
- **BLOCKED** — missing credential, safe destination, OS permission, signing input, or explicit approval.
- **FAIL** — behavior is incorrect and must be fixed before beta.

## Automated release gate

Run:

```bash
Scripts/m9_release_gate.sh
```

Required outcomes:

- [x] `xcodegen generate` PASS
- [x] `xcodebuild -list` PASS
- [x] Debug build PASS
- [x] Full XCTest suite PASS — 132 tests, 0 failures
- [x] `git diff --check` PASS
- [x] Release archive PASS
- [x] DMG creation PASS
- [x] Built bundle identity is `Diak` / `com.uberkiwi.diak` / executable `Diak`
- [x] Codesign inspection recorded
- [x] Report saved under `build/m9/` — latest local report: `build/m9/M9_RELEASE_GATE_20260510-051715.md`

## In-app beta readiness

- [x] Settings contains **Beta Readiness**.
- [x] Internal beta verdict is not falsely marked full public release.
- [x] External distribution remains BLOCKED unless signing/notary evidence exists.
- [x] Safe connector writes are BLOCKED unless Nick provides safe destinations and explicit approval.
- [x] Local Diak-shaped daemon contract passes with the QA compatibility daemon; production Hermes execution remains separately classified as not proven until real chat/session persistence is verified against a live Hermes Agent daemon.

## Product polish

- [x] Sidebar header says `Diak`.
- [x] Window/app bundle/menu surfaces say `Diak`.
- [x] Runtime references say `Hermes Agent` / `Hermes Engine` where appropriate.
- [x] No product-facing `Hermes Desktop` remains in app source.
- [x] First-run onboarding is visually clean from a DMG-copy launch after unrelated macOS prompts were cleared; evidence: `qa/diak-m9-clean-first-run-20260510-080224/M9_CLEAN_FIRST_RUN_AND_DAEMON_EVIDENCE_REPORT.md`.

## Live dogfood gates

These are required before calling beta fully green:

- [x] Fresh install from DMG.
- [ ] First launch onboarding complete/skip persists across relaunch — not completed by automation in this run because local Accessibility privileges are disabled; first-run visual state itself is PASS.
- [x] Offline Hermes Agent state is truthful and non-crashing.
- [ ] Production Hermes Agent chat task completes with durable session/model execution evidence. Local contract probe is PASS with the QA compatibility daemon on `127.0.0.1:8765`, but this is not production execution.
- [ ] Session created by live chat appears in session history.
- [ ] Approval preview appears before any risky action.
- [ ] Skill list/detail works; true skill execution classified with artifact evidence or marked PARTIAL/BLOCKED.
- [ ] Automation create/run/dry-run classified with history evidence or marked PARTIAL/BLOCKED.
- [ ] Memory edit/delete/pin verified against live daemon or marked PARTIAL/BLOCKED.
- [ ] Menu bar popover opens.
- [ ] Quick Prompt opens with `⇧⌘K`.
- [ ] Compact window command works.

## External distribution gates

Required before public/external release:

- [ ] Developer ID Application certificate installed.
- [ ] Local untracked export options configured.
- [ ] Notary profile configured outside git.
- [ ] Exported app/DMG signed with Developer ID.
- [ ] Notarization succeeds.
- [ ] Stapling succeeds.
- [ ] Gatekeeper assessment passes on clean Mac account/VM.
- [ ] Sparkle 2 integrated if auto-update UX is required for that beta/public channel.

## M9 release decision

- Internal dogfood/private beta: PASS / PARTIAL / BLOCKED / FAIL
- External distribution: PASS / BLOCKED / FAIL
- Critical blockers:
- Owner/date for next dogfood pass:
