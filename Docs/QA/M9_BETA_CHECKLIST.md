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
- [x] Live daemon E2E is PARTIAL until chat/session persistence is proven against a live Hermes Agent daemon.

## Product polish

- [x] Sidebar header says `Diak`.
- [x] Window/app bundle/menu surfaces say `Diak`.
- [x] Runtime references say `Hermes Agent` / `Hermes Engine` where appropriate.
- [x] No product-facing `Hermes Desktop` remains in app source.
- [ ] First-run onboarding is visually clean on a clean macOS account or VM. Latest local DMG-copy launch rendered onboarding but was obstructed by unrelated macOS dialogs; evidence: `qa/diak-m9-dogfood-20260510-054048/M9_DOGFOOD_EVIDENCE_REPORT.md`.

## Live dogfood gates

These are required before calling beta fully green:

- [ ] Fresh install from DMG.
- [ ] First launch onboarding complete/skip persists across relaunch.
- [ ] Offline Hermes Agent state is truthful and non-crashing.
- [ ] Live Hermes Agent chat task completes or returns a truthful user-visible failure. Latest probe: BLOCKED because no Diak-compatible daemon listens on `127.0.0.1:8765`; Hermes API Server currently exposes a different `/v1/...` contract if enabled.
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
