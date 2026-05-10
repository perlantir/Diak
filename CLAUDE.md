# Diak

Diak is a premium SwiftUI macOS app that acts as a native UI/control center for Hermes Agent.

## Product boundary

- SwiftUI owns the Mac UI, navigation, settings, approvals, notifications, menu bar, quick prompt, and local UX.
- Hermes Agent remains the updatable engine accessed through a local API/daemon boundary.
- Do not reimplement Hermes internals inside the Mac app.
- Public app surfaces should say **Diak**. Use **Hermes Agent** / **Hermes Engine** only when referring to the runtime.

## Build discipline

- Build in small verified milestones and do not jump ahead of the current milestone.
- Completed locally: M0 app shell/design system/daemon status, M1 sessions/chat foundation, M2 approvals/action evidence, M3 settings/profiles/models/tools, M4 automations UI/API boundary, M5 connectors UI/API boundary, M6 skills/memory UI/API boundary, M7 native Mac integrations, and M8 release-readiness/Diak branding/QA documentation.
- Use reusable SwiftUI components and semantic design tokens.
- Run `xcodebuild -list`, build, and tests before reporting done.
- Do not commit generated build artifacts, signing credentials, notary profiles, Sparkle private keys, or local export option plists.

## Design source

Use the files under `Docs/` as the source of truth, especially:

- `Docs/HERMES_DESKTOP_FULL_BUILD_SPEC.md`
- `Docs/HERMES_DESKTOP_DESIGN_BRIEF.md`
- `Docs/DESIGN_PACKAGE_REVIEW_AND_BUILD_HANDOFF.md`
- `Docs/Plans/M8_RELEASE_READINESS_BRANDING_QA.md`
- `Docs/Release/M8_RELEASE_READINESS.md`
- `Docs/Release/UPDATER_STRATEGY.md`
- `Docs/QA/M8_TRUE_E2E_QA_CHECKLIST.md`
- `Docs/DesignPackage/hermes_desktop_design_package/tokens/hermes_notion_inspired_tokens.json`
- `Docs/DesignPackage/hermes_desktop_design_package/Hermes_Desktop_All_Screens_Contact_Sheet.png`
