# Hermes Desktop

Hermes Desktop is a premium SwiftUI macOS app that acts as a native UI/control center for Hermes Agent.

## Product boundary

- SwiftUI owns the Mac UI, navigation, settings, approvals, notifications, menu bar, quick prompt, and local UX.
- Hermes Agent remains the updatable engine accessed through a local API/daemon boundary.
- Do not reimplement Hermes internals inside the Mac app.

## Build discipline

- Build in small verified milestones and do not jump ahead of the current milestone.
- Completed locally: M0 app shell/design system/daemon status, M1 sessions/chat foundation, and M2 approvals/action evidence.
- Current milestone: M3 settings/profiles/models/tools. Build one-stop configuration UI and typed API boundary/mock behavior; do not implement automations, real connectors/OAuth, skills, memory, menu bar, global hotkey, packaging/updater, or native integrations yet.
- Use reusable SwiftUI components and semantic design tokens.
- Run `xcodebuild -list`, build, and tests before reporting done.
- Do not commit generated build artifacts.

## Design source

Use the files under `Docs/` as the source of truth, especially:

- `Docs/HERMES_DESKTOP_FULL_BUILD_SPEC.md`
- `Docs/HERMES_DESKTOP_DESIGN_BRIEF.md`
- `Docs/DESIGN_PACKAGE_REVIEW_AND_BUILD_HANDOFF.md`
- `Docs/DesignPackage/hermes_desktop_design_package/tokens/hermes_notion_inspired_tokens.json`
- `Docs/DesignPackage/hermes_desktop_design_package/Hermes_Desktop_All_Screens_Contact_Sheet.png`
