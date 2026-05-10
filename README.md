# Hermes Desktop

A premium SwiftUI macOS app that acts as a native UI/control center for Hermes Agent.

This repo currently contains M0: app shell, design system tokens, daemon health/status with mock + URLSession clients, onboarding foundation, Settings > Hermes Engine, daemon offline/reconnect state, and tests.

## Requirements

- macOS 13.0+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Generate the Xcode project

The `.xcodeproj` is generated from `project.yml` and is intentionally git-ignored.

```bash
xcodegen generate
```

## Build

```bash
xcodebuild -list
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
```

## Test

```bash
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
```

## Open in Xcode

```bash
open HermesDesktop.xcodeproj
```

## What is in M0

- SwiftUI macOS app entry (`HermesDesktopApp`)
- Three-pane-ready `NavigationSplitView` shell with sidebar nav placeholders for Home, Sessions, Automations, Connectors, Skills, Memory, Projects, Action Center, Settings
- Optional/collapsible right inspector placeholder
- Design system primitives derived from `Docs/DesignPackage/.../tokens/hermes_notion_inspired_tokens.json`:
  - semantic colors with dark/light variants
  - spacing, radius, typography helpers
  - reusable `HermesCard`, `HermesButton`, `StatusBadge`, `RiskBadge`, `SidebarItem`, `StatusRow`, `EmptyStateView`, `ErrorStateView`
- Onboarding foundation: Welcome, Hermes Engine Setup, Model Provider Setup, Safety Permissions
- Settings > Hermes Engine status page (daemon status, version, profile, restart/reconnect)
- `HermesAPIClient` protocol with `MockHermesAPIClient` and `URLSessionHermesAPIClient` (`GET /health`, `GET /version`)
- Daemon offline/reconnect sheet
- Tests for model decoding, mock API client, and daemon view model state

## What is **not** in M0 (intentional)

- Full chat / streaming
- Real automations, connectors, OAuth, skills, memory
- Menu bar extra and global hotkey
- Real Hermes daemon installation flow

These will be addressed in subsequent milestones (see `Docs/HERMES_DESKTOP_FULL_BUILD_SPEC.md`).
