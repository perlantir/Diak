# Claude Code Prompt — Hermes Desktop M0

Copy/paste this into Claude Code from the Hermes Desktop repo root once the repo is initialized.

```text
You are working on Hermes Desktop, a premium SwiftUI macOS app that serves as a native UI/control center for Hermes Agent.

Project goal:

Build M0 only: app shell + design system + Hermes daemon status/onboarding foundation. Do not implement full chat, automations, connectors, or skills yet.

Source docs/design assets:

- Full build spec:
  Docs/HERMES_DESKTOP_FULL_BUILD_SPEC.md
- Design brief:
  Docs/HERMES_DESKTOP_DESIGN_BRIEF.md
- Design package review/build handoff:
  Docs/DESIGN_PACKAGE_REVIEW_AND_BUILD_HANDOFF.md
- Design package root:
  Docs/DesignPackage/hermes_desktop_design_package/
- Handoff:
  Docs/DesignPackage/hermes_desktop_design_package/handoff/Hermes_Desktop_Design_Handoff.md
- Tokens:
  Docs/DesignPackage/hermes_desktop_design_package/tokens/hermes_notion_inspired_tokens.json
- Contact sheet:
  Docs/DesignPackage/hermes_desktop_design_package/Hermes_Desktop_All_Screens_Contact_Sheet.png
- Key M0 artboards:
  Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/01_01-onboarding-welcome.svg
  Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/02_02-onboarding-hermes-engine-setup.svg
  Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/03_03-onboarding-model-provider-setup.svg
  Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/04_04-onboarding-safety-permissions.svg
  Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/29_29-settings-general.svg
  Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/30_30-settings-hermes-engine.svg
  Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/45_45-modal-daemon-offline-reconnect.svg
  Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/48_48-responsive-standard-desktop-window.svg
  Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/49_49-responsive-wide-window-inspector.svg
  Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/50_50-dark-mode-canonical.svg
  Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/51_51-light-mode-canonical.svg
  Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/53_53-component-system-tokens.svg

M0 scope:

1. Create/verify a SwiftUI macOS app skeleton.
2. Implement the first design system primitives from the token JSON:
   - semantic colors with dark/light variants
   - spacing constants
   - radius constants
   - typography helpers
   - card, badge, sidebar item, status row, empty/error state primitives
3. Implement the app shell:
   - native macOS app entry
   - main `NavigationSplitView` or equivalent three-pane-ready shell
   - left sidebar with top-level nav placeholders:
     - Home
     - Sessions
     - Automations
     - Connectors
     - Skills
     - Memory
     - Projects
     - Action Center
     - Settings
   - center content area
   - optional/collapsible right inspector placeholder
4. Implement onboarding foundation:
   - Welcome
   - Hermes Engine Setup
   - Model Provider Setup placeholder
   - Safety Permissions placeholder
   Use the designs as visual direction, but keep data mocked for now.
5. Implement Settings > Hermes Engine status page:
   - daemon status
   - version/profile fields
   - start/restart/reconnect buttons as non-destructive placeholders unless a safe local client exists
6. Implement Hermes API client boundary:
   - `HermesAPIClient` protocol
   - `MockHermesAPIClient`
   - `URLSessionHermesAPIClient` with `GET /health` and `GET /version` if endpoint exists/configurable
   - typed models for health/version/status
   - no hardcoded secrets
7. Implement daemon offline/reconnect modal/sheet state.
8. Add tests:
   - model decoding tests
   - mock API client tests
   - view model state tests for connected/offline/loading/error
9. Add README or docs explaining how to run/build M0.

Constraints:

- Do not implement full chat yet.
- Do not implement real connector OAuth yet.
- Do not reimplement Hermes internals.
- Do not shell out to destructive commands.
- Keep Hermes as an external/updatable engine accessed through a local API boundary.
- Use reusable components; do not hardcode styling in every screen.
- Prefer native SwiftUI/macOS patterns while matching the design direction.

Suggested file organization:

HermesDesktop/
  App/
  Sources/HermesDesktop/
    DesignSystem/
    Features/AppShell/
    Features/Onboarding/
    Features/Settings/
    Features/DaemonStatus/
    Services/HermesAPI/
    Models/
  Tests/HermesDesktopTests/
  Docs/

Verification required:

- Run `xcodebuild -list`.
- Run the correct `xcodebuild ... build` command for the macOS target.
- Run tests.
- Report exact commands and results.
- Report changed files.
- Report any blockers or decisions needed.

Definition of done:

- The app launches/builds as a macOS SwiftUI app.
- M0 screens are navigable.
- Design system tokens are centralized.
- Mock daemon status works.
- Offline/reconnect state works visually.
- Tests pass.
- No generated build artifacts are committed.
```
