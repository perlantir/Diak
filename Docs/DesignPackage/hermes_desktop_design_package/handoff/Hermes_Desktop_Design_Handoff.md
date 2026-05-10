# Hermes Desktop — Design Handoff

Date: 2026-05-10

This package contains a full Notion-inspired, Mac-native design pass for Hermes Desktop. The design is original and does not copy Notion proprietary screens or branding; it uses a similar calm editorial feel: warm neutral backgrounds, precise typography, low-contrast borders, compact controls, and clear document-like hierarchy.

## Package contents

- `artboards/svg/` — 53 editable vector artboards suitable for Figma import.
- `artboards/png/` — PNG previews for each artboard.
- `Hermes_Desktop_All_Screens_Contact_Sheet.png` — thumbnail overview.
- `figma_plugin/` — local Figma importer plugin that creates pages and imports every artboard.
- `tokens/hermes_notion_inspired_tokens.json` — colors, type, radius, spacing, SwiftUI notes.
- `index.html` — local gallery of all screens.

## Important note about .fig files

The tools available here do not expose a function to create or export a native `.fig` file directly. The closest editable equivalent is included: SVG artboards plus a Figma development plugin that imports them into Figma as editable layers/groups. After running the plugin in Figma, use Figma's local save/export flow to create the `.fig` file.

## Visual direction

- Native Mac titlebar, sidebar navigation, preferences window, sheets, menu bar popover, and quick prompt.
- Notion-style warmth: off-white surfaces, small card radii, compact typography, restrained palette.
- Dark mode primary: low-contrast charcoal surfaces with warm gray borders.
- Light mode secondary: white/off-white shell with subtle dividers and text-first layout.
- No AI-purple gradient clichés; color is reserved for state, risk, and attention.

## Implementation mapping

### M0 app shell / daemon status
Screens: 01–04, 29–30, 45, 48–51.

### M1 chat
Screens: 05–07, 13, 47–51.

### M2 approvals/action evidence
Screens: 08–11, 37–39, 52.

### M3 settings/models/tools
Screens: 29–33, 40, 45.

### M4 automations
Screens: 14–17, 43.

### M5 connectors
Screens: 18–21, 39, 41.

### M6 skills/memory
Screens: 22–26, 46.

### M7 menu bar/global hotkey/native integrations
Screens: 34–36, 47.

## Screen index

- 01. 01 Onboarding Welcome — `artboards/svg/01_01-onboarding-welcome.svg`
- 02. 02 Onboarding Hermes Engine Setup — `artboards/svg/02_02-onboarding-hermes-engine-setup.svg`
- 03. 03 Onboarding Model Provider Setup — `artboards/svg/03_03-onboarding-model-provider-setup.svg`
- 04. 04 Onboarding Safety Permissions — `artboards/svg/04_04-onboarding-safety-permissions.svg`
- 05. 05 Main App Empty Home New Chat — `artboards/svg/05_05-main-app-empty-home-new-chat.svg`
- 06. 06 Active Chat Streaming Response — `artboards/svg/06_06-active-chat-streaming-response.svg`
- 07. 07 Chat With Tool Activity Visible — `artboards/svg/07_07-chat-with-tool-activity-visible.svg`
- 08. 08 Chat With Pending Approval — `artboards/svg/08_08-chat-with-pending-approval.svg`
- 09. 09 Right Inspector Activity — `artboards/svg/09_09-right-inspector-activity.svg`
- 10. 10 Right Inspector Artifacts — `artboards/svg/10_10-right-inspector-artifacts.svg`
- 11. 11 Action Center — `artboards/svg/11_11-action-center.svg`
- 12. 12 Sessions History List — `artboards/svg/12_12-sessions-history-list.svg`
- 13. 13 Session Detail Resume — `artboards/svg/13_13-session-detail-resume.svg`
- 14. 14 Automations Dashboard — `artboards/svg/14_14-automations-dashboard.svg`
- 15. 15 Create Automation Conversational Builder — `artboards/svg/15_15-create-automation-conversational-builder.svg`
- 16. 16 Automation Review Config Screen — `artboards/svg/16_16-automation-review-config-screen.svg`
- 17. 17 Automation Detail Run History — `artboards/svg/17_17-automation-detail-run-history.svg`
- 18. 18 Connectors Catalog — `artboards/svg/18_18-connectors-catalog.svg`
- 19. 19 Connector Detail Connected Write Capable — `artboards/svg/19_19-connector-detail-connected-write-capable.svg`
- 20. 20 Connector Detail Missing Scope Error — `artboards/svg/20_20-connector-detail-missing-scope-error.svg`
- 21. 21 Connector Setup Flow — `artboards/svg/21_21-connector-setup-flow.svg`
- 22. 22 Skills Library — `artboards/svg/22_22-skills-library.svg`
- 23. 23 Skill Detail — `artboards/svg/23_23-skill-detail.svg`
- 24. 24 Create Skill From Session Review — `artboards/svg/24_24-create-skill-from-session-review.svg`
- 25. 25 Memory Dashboard — `artboards/svg/25_25-memory-dashboard.svg`
- 26. 26 Memory Item Edit Delete — `artboards/svg/26_26-memory-item-edit-delete.svg`
- 27. 27 Projects List — `artboards/svg/27_27-projects-list.svg`
- 28. 28 Project Detail Settings — `artboards/svg/28_28-project-detail-settings.svg`
- 29. 29 Settings General — `artboards/svg/29_29-settings-general.svg`
- 30. 30 Settings Hermes Engine — `artboards/svg/30_30-settings-hermes-engine.svg`
- 31. 31 Settings Models Providers — `artboards/svg/31_31-settings-models-providers.svg`
- 32. 32 Settings Tools Permissions — `artboards/svg/32_32-settings-tools-permissions.svg`
- 33. 33 Settings Security Privacy — `artboards/svg/33_33-settings-security-privacy.svg`
- 34. 34 Menu Bar Popover — `artboards/svg/34_34-menu-bar-popover.svg`
- 35. 35 Global Quick Prompt — `artboards/svg/35_35-global-quick-prompt.svg`
- 36. 36 Notification Deep Link Behavior — `artboards/svg/36_36-notification-deep-link-behavior.svg`
- 37. 37 Modal Approval Terminal Command — `artboards/svg/37_37-modal-approval-terminal-command.svg`
- 38. 38 Modal Approval File Write Diff — `artboards/svg/38_38-modal-approval-file-write-diff.svg`
- 39. 39 Modal Approval Connector Send Post — `artboards/svg/39_39-modal-approval-connector-send-post.svg`
- 40. 40 Modal Connect Provider API Key — `artboards/svg/40_40-modal-connect-provider-api-key.svg`
- 41. 41 Modal Connect OAuth Account — `artboards/svg/41_41-modal-connect-oauth-account.svg`
- 42. 42 Modal Add Project Trust Folder — `artboards/svg/42_42-modal-add-project-trust-folder.svg`
- 43. 43 Modal Create Automation Final Review — `artboards/svg/43_43-modal-create-automation-final-review.svg`
- 44. 44 Modal Destructive Delete Confirmation — `artboards/svg/44_44-modal-destructive-delete-confirmation.svg`
- 45. 45 Modal Daemon Offline Reconnect — `artboards/svg/45_45-modal-daemon-offline-reconnect.svg`
- 46. 46 Modal Skill Draft Review — `artboards/svg/46_46-modal-skill-draft-review.svg`
- 47. 47 Responsive Compact Window — `artboards/svg/47_47-responsive-compact-window.svg`
- 48. 48 Responsive Standard Desktop Window — `artboards/svg/48_48-responsive-standard-desktop-window.svg`
- 49. 49 Responsive Wide Window Inspector — `artboards/svg/49_49-responsive-wide-window-inspector.svg`
- 50. 50 Dark Mode Canonical — `artboards/svg/50_50-dark-mode-canonical.svg`
- 51. 51 Light Mode Canonical — `artboards/svg/51_51-light-mode-canonical.svg`
- 52. 52 Empty Loading Error States Matrix — `artboards/svg/52_52-empty-loading-error-states-matrix.svg`
- 53. 53 Component System Tokens — `artboards/svg/53_53-component-system-tokens.svg`

## SwiftUI component guidance

Use `NavigationSplitView` for sidebar/content/inspector. Keep the chat workspace visually quiet; expose advanced details in the inspector and expandable cards. Use sheets for approvals and critical connection/configuration flows. Prefer SwiftUI `Form`, `List`, `Section`, and compact controls in preferences, but avoid default heavy table chrome inside the main product surfaces.

### Core components

- `SidebarItem(icon:title:badge:active:)`
- `SessionRow(title:preview:timestamp:project:status:badges:)`
- `MessageBlock(role:content:streaming:)`
- `ToolCallCard(status:title:summary:expanded:)`
- `ApprovalCard(risk:action:target:preview:actions:)`
- `InspectorPanel(tab:items:)`
- `AutomationCard(status:schedule:nextRun:actions:)`
- `ConnectorCard(status:capabilities:)`
- `CapabilityRow(mode:risk:approvalRequired:availability:)`
- `SkillCard(state:compatibleSurfaces:)`
- `MemoryItemRow(source:category:actions:)`
- `ProjectRow(trust:gitStatus:defaultPolicy:)`
- `RiskBadge(level:)` and `StatusBadge(status:)`

### Safety UX rules

1. Every side effect shows what, why, where, risk, and exact preview.
2. High and critical risk never hide behind a generic confirmation.
3. Approval history persists in Action Center with source session/job.
4. Connector capability modes are explicit: read, write, destructive, automation-safe, approval-required.
5. Automation jobs with future side effects require a final review sheet.

### Typography

Use macOS system typography in implementation:

- Display: `.system(size: 30, weight: .bold)`
- Title: `.system(size: 22, weight: .semibold)`
- Section: `.system(size: 14, weight: .semibold)`
- Body: `.system(size: 13, weight: .regular)`
- Caption: `.system(size: 11, weight: .medium)`
- Code/diff/terminal: `.system(.body, design: .monospaced)`

### Accessibility

- Do not rely on color alone for risk/status. Include status text and iconography.
- Approval actions should have explicit labels: “Approve Once”, “Deny”, “Modify”.
- Ensure risk badges meet contrast in both modes and include VoiceOver labels.
- Respect reduced transparency/motion for native macOS effects.
