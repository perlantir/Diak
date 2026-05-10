# Hermes Desktop — Design Package Review + SwiftUI Build Handoff

Date: 2026-05-10
Design package source: `/Users/perlantir/Projects/HermesDesktop/Docs/DesignPackage/hermes_desktop_design_package/`

## Package inventory

- Full contact sheet: `Hermes_Desktop_All_Screens_Contact_Sheet.png`
- Local gallery: `index.html`
- Manifest: `screen_manifest.json`
- Handoff: `handoff/Hermes_Desktop_Design_Handoff.md`
- Tokens: `tokens/hermes_notion_inspired_tokens.json`
- Figma importer plugin: `figma_plugin/`
- Artboards: 53 SVG + 53 PNG

## Design direction

The package is a complete Notion-inspired, Mac-native design pass for Hermes Desktop:

- Warm neutral light mode surfaces.
- Dark-mode-forward operational screens.
- Compact Mac utility density.
- Native shell patterns: sidebar, split view, inspector, sheets, preferences, menu bar, quick prompt.
- Clear trust/safety focus: approval modals, risk badges, connector scopes, project trust, daemon reconnect, destructive confirmations.
- No generic AI-gradient look.

This is a strong direction for a premium SwiftUI Mac app.

## Coverage assessment

The design package covers the requested full product scope well:

- Onboarding: screens 01–04
- Main chat/task workspace: 05–08
- Inspector/action evidence: 09–10
- Action Center: 11
- Sessions/history: 12–13
- Automations: 14–17 + 43
- Connectors: 18–21 + 39–41
- Skills: 22–24 + 46
- Memory: 25–26
- Projects/workspaces: 27–28 + 42
- Preferences/settings: 29–33
- Menu bar/global prompt/notifications: 34–36
- Critical modals: 37–46
- Responsive/dark/light/state matrix/tokens: 47–53

## Implementation milestone mapping

Use the designer's mapping as the build order:

### M0 — App shell / daemon status

Screens: 01–04, 29–30, 45, 48–51

Build:

- SwiftUI app skeleton
- `NavigationSplitView` shell
- onboarding shell
- Hermes daemon health/status screen
- settings engine page
- daemon offline modal
- dark/light tokens

### M1 — Chat

Screens: 05–07, 13, 47–51

Build:

- session list basics
- new chat screen
- message timeline
- streaming response state
- tool activity cards
- compact/standard/wide layout behavior

### M2 — Approvals / action evidence

Screens: 08–11, 37–39, 52

Build:

- approval cards
- approval modal shell
- terminal command approval
- file diff approval
- connector send/post approval
- action center
- empty/loading/error state components

### M3 — Settings / models / tools

Screens: 29–33, 40, 45

Build:

- Preferences window
- provider/API-key modal
- model/provider settings
- tools/permissions settings
- security/privacy settings
- daemon reconnect/restart states

### M4 — Automations

Screens: 14–17, 43

Build:

- automation list/dashboard
- conversational builder
- review/config screen
- run history
- final review modal

### M5 — Connectors

Screens: 18–21, 39, 41

Build:

- connector catalog
- connector detail
- missing scope/error state
- setup flow
- OAuth account modal
- connector write approval integration

### M6 — Skills / memory

Screens: 22–26, 46

Build:

- skills library
- skill detail
- create skill review
- memory dashboard
- memory edit/delete

### M7 — Native Mac integrations

Screens: 34–36, 47

Build:

- `MenuBarExtra`
- global quick prompt
- notification deep-link behavior
- compact floating window state

## SwiftUI design system to implement first

Create semantic tokens before building screens.

### Tokens

Source: `tokens/hermes_notion_inspired_tokens.json`

Spacing:

- xs: 4
- sm: 8
- md: 12
- lg: 16
- xl: 24
- xxl: 32

Radius:

- control: 7
- card: 10
- panel: 14
- window/sheet: 18

Typography:

- Caption: 11 / 14 / medium
- Body: 13 / 18 / regular
- Body strong: 13 / 18 / semibold
- Section: 14 / 20 / semibold
- Title: 22 / 28 / bold
- Display: 30 / 38 / bold
- Code/diff/terminal: monospaced

### Required primitive components

- `HermesTheme`
- `HermesSpacing`
- `HermesRadius`
- `HermesTypography`
- `HermesButton`
- `HermesCard`
- `StatusBadge`
- `RiskBadge`
- `SidebarItem`
- `SessionRow`
- `MessageBlock`
- `ToolCallCard`
- `ApprovalCard`
- `ApprovalSheet`
- `InspectorPanel`
- `AutomationCard`
- `ConnectorCard`
- `CapabilityRow`
- `SkillCard`
- `MemoryItemRow`
- `ProjectRow`
- `EmptyStateView`
- `ErrorStateView`
- `CommandPreviewView`
- `DiffPreviewView`

## Key risks to resolve before/while building

1. **Custom Mac UI vs default controls**
   - The design is Mac-native conceptually but visually custom. Decide early where to use default SwiftUI/AppKit styling and where to use custom components.

2. **Accessibility**
   - Dense labels and low-contrast surfaces require contrast checks, VoiceOver labels, keyboard focus states, and minimum hit targets.

3. **State explosion**
   - Sessions, tools, connectors, daemon, models, automations, projects, notifications, and approvals all have many statuses. Implement a shared status taxonomy.

4. **Modal proliferation**
   - Approval/connect/setup/review/destructive modals should use reusable shells, not one-off implementations.

5. **Responsive behavior**
   - Need exact rules for compact/standard/wide layouts: inspector collapse, sidebar behavior, composer sizing, long diff overflow, modal constraints.

6. **Keyboard and menu commands**
   - Design implies a pro Mac app. Implementation needs command menu architecture: new chat, search, quick prompt, toggle inspector/sidebar, stop, retry, settings, action center.

7. **Security/privacy redaction**
   - Terminal/file/connector previews need redaction and safe logging policies.

## Build recommendation

Use Claude Code as primary builder for architecture-heavy SwiftUI + Hermes daemon/API work. Use Codex later for bounded tests, small components, and bug fixes.

First build should not attempt the whole product. Start with M0:

- repo/app skeleton
- design system tokens
- app shell
- daemon health/status mock + real client boundary
- onboarding shell
- daemon offline state
- build/test verification

## Acceptance criteria for M0

- SwiftUI macOS app builds with `xcodebuild`.
- App uses semantic design tokens from the package.
- Main shell layout matches the design direction.
- App can show Hermes daemon health from a mocked client and, if available, a real local endpoint.
- Daemon offline/reconnect state is represented.
- Onboarding first screens exist as navigable placeholders.
- Settings > Hermes Engine exists as a functional status page.
- Screens are built using reusable primitives, not one-off duplicated styling.
- Light/dark mode works using semantic colors.
- Tests cover API models/client mock and key view model states.

## Design asset paths for implementation

- Contact sheet:
  - `Docs/DesignPackage/hermes_desktop_design_package/Hermes_Desktop_All_Screens_Contact_Sheet.png`
- Gallery:
  - `Docs/DesignPackage/hermes_desktop_design_package/index.html`
- Tokens:
  - `Docs/DesignPackage/hermes_desktop_design_package/tokens/hermes_notion_inspired_tokens.json`
- Handoff:
  - `Docs/DesignPackage/hermes_desktop_design_package/handoff/Hermes_Desktop_Design_Handoff.md`
- Artboard SVGs:
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/`
- Artboard PNGs:
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/png/`
