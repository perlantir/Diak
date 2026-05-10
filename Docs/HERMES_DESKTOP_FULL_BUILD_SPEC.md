# Hermes Desktop — Full-Scale Build Spec

Date: 2026-05-09  
Owner: Nick Gallick  
Product direction: Premium Mac-native UI for Hermes Agent  
Primary client: SwiftUI macOS app  
Agent engine: Hermes Agent daemon/API, not a fork  
Status: Draft v1 for implementation planning

---

## 1. Product thesis

Hermes Desktop is a premium Mac-native control center for Hermes Agent.

It gives Nick and future users a simple, beautiful, one-stop Mac app to:

- chat with a powerful local/cloud agent
- run coding, research, file, browser, and system tasks
- approve risky actions safely
- connect external tools/accounts
- create automations in natural language
- manage skills, memory, sessions, models, and tool permissions
- receive native notifications and use global Mac shortcuts

The product should feel like a first-class Mac app, not a website in a wrapper.

The Mac app must not reimplement Hermes internals. Hermes remains the updatable engine. The Mac app is a native SwiftUI client plus Mac-specific integrations.

---

## 2. Product positioning

### 2.1 One-sentence positioning

Hermes Desktop is a clean Mac-native AI operator that lets you chat with Hermes, connect your tools, approve actions, and automate recurring work from one polished desktop app.

### 2.2 Comparable products

Hermes Desktop sits between:

- ChatGPT Desktop: polished chat, but limited local agent control.
- Claude Desktop: MCP-friendly, but not a full autonomous local operator.
- Raycast AI: fast launcher/workflows, but less deep autonomous agent/session system.
- Manus/Handle-style agent app: task/action/automation model, but Mac-native and powered by Hermes.
- Automator/Shortcuts: automation, but natural-language agent-first.

### 2.3 Product principles

1. Native Mac feel first.
2. Hermes engine remains upgradeable.
3. Every external or destructive action is previewed and approval-gated.
4. Automation setup should be conversational but inspectable.
5. Users should always know what the agent did, what it touched, and what it is waiting for.
6. Simple default UI, powerful inspector panels when needed.
7. No fake connector claims: status and capabilities must be truthful.

---

## 3. Target users

### 3.1 Primary user: technical founder / builder

Needs:

- local coding assistance
- repo/project workflows
- browser research
- recurring automations
- connector actions
- file and terminal use with safety
- deep control without ugly configuration

### 3.2 Secondary user: operator / knowledge worker

Needs:

- email/slack/github summaries
- calendar/task automations
- document drafting
- approvals before sending/posting
- easy setup

### 3.3 Future user: power-user teams

Needs:

- profiles
- shared skills
- team-approved connectors
- policy controls
- audit logs

Team features are not v1, but architecture should not block them.

---

## 4. Jobs to be done

1. When I have a task, I want to tell the agent naturally and see it work safely.
2. When the agent wants to do something risky, I want a clear native approval prompt.
3. When I repeat work, I want to turn it into an automation without writing cron syntax.
4. When I connect a service, I want to know exactly what Hermes can do with it.
5. When an automation runs, I want history, outputs, and failure reasons.
6. When Hermes gains updates, I want the Mac app to benefit without a rewrite.
7. When I use local files, terminal, browser, or screenshots, I want Mac-native permissions and UX.

---

## 5. Scope model

This spec maps the full product, not only MVP.

Implementation should still be staged in milestones:

- M0: architecture spike and Hermes API contract
- M1: native chat/task client
- M2: approvals and action evidence
- M3: sessions, profiles, settings, models
- M4: automation builder/dashboard
- M5: connector manager
- M6: skills/memory UI
- M7: Mac-native power features
- M8: packaging, updater, signing, notarization
- M9: polish, QA, beta

---

## 6. Non-goals

Do not do these unless explicitly approved later:

- Do not rewrite Hermes Agent in Swift.
- Do not copy/paste Hermes internals into the Mac app.
- Do not build a custom agent runtime.
- Do not reimplement model/tool dispatch.
- Do not store secrets in UserDefaults or plaintext files.
- Do not claim a connector is write-capable unless verified.
- Do not bypass Hermes safety/approval semantics.
- Do not build a full Handle clone before shipping the core desktop experience.

---

## 7. System architecture

### 7.1 High-level architecture

```text
HermesDesktop.app
  SwiftUI UI
  AppKit integration layer
  Keychain helper
  Notification/global hotkey/file picker/screenshot services
  Hermes API client
        |
        | localhost HTTP + SSE/WebSocket
        v
Hermes Daemon / API Server
  Hermes Agent core
  sessions
  model/provider routing
  tools/toolsets
  skills
  memory
  cron jobs
  gateway
  MCP
  approvals
  action/event stream
        |
        v
Local system + external services
  terminal/files/browser
  MCP servers
  Gmail/GitHub/Slack/etc.
  local models/cloud providers
```

### 7.2 Core decision

The SwiftUI app is the product UI. Hermes is the engine.

The boundary is a stable local API contract. The app should not directly parse Hermes internal SQLite/session files except as a temporary migration/debug fallback.

### 7.3 Hermes daemon responsibilities

Hermes daemon owns:

- sessions and messages
- prompt/model/tool loop
- tool schemas and tool execution
- subagents/delegation
- memory/user profile
- skills loading/installing/running
- cron jobs
- gateway/platform adapters
- MCP server config/tool discovery
- provider config/migrations
- approval requests
- action evidence/events
- tool safety checks

### 7.4 SwiftUI app responsibilities

Mac app owns:

- native navigation and layout
- chat/task composition UI
- event stream rendering
- approval sheets
- connector setup/status UI
- automation creation/editing UI
- skill browser UI
- settings/preferences UI
- Mac permissions and integrations
- notifications
- global hotkeys/menu bar
- packaging, update UX, first-run onboarding

---

## 8. Hermes local API contract

Hermes Desktop needs a supported local API mode. If current Hermes API/gateway is insufficient, add a first-class desktop daemon API.

### 8.1 Transport

Preferred:

- HTTP JSON for commands
- SSE for streaming session events
- WebSocket optional for bidirectional realtime

Default local address:

- `http://127.0.0.1:<dynamic-or-configured-port>`

Security:

- bind to localhost only by default
- random session token generated at daemon start
- app stores daemon token in memory and Keychain if persistent
- no public LAN exposure unless explicitly enabled

### 8.2 Health and daemon lifecycle

Endpoints:

- `GET /health`
- `GET /version`
- `POST /daemon/shutdown`
- `GET /daemon/status`
- `POST /daemon/restart`
- `GET /daemon/logs?tail=200`

Health response:

```json
{
  "service": "hermes-daemon",
  "status": "ok",
  "version": "x.y.z",
  "build": {
    "gitCommit": "...",
    "builtAt": "..."
  },
  "profile": "default",
  "timestamp": "..."
}
```

### 8.3 Sessions and messages

Endpoints:

- `GET /sessions`
- `POST /sessions`
- `GET /sessions/{sessionId}`
- `PATCH /sessions/{sessionId}`
- `DELETE /sessions/{sessionId}`
- `POST /sessions/{sessionId}/messages`
- `GET /sessions/{sessionId}/events`
- `POST /sessions/{sessionId}/stop`
- `POST /sessions/{sessionId}/retry`
- `POST /sessions/{sessionId}/branch`

Message request:

```json
{
  "text": "Summarize this folder",
  "attachments": [
    { "type": "file", "path": "/Users/nick/Desktop/report.pdf" }
  ],
  "skills": ["dogfood"],
  "toolsets": ["terminal", "file", "browser"],
  "profile": "default",
  "workdir": "/Users/nick/Projects/app"
}
```

### 8.4 Event stream

Event types:

- `session.created`
- `message.user`
- `message.assistant.delta`
- `message.assistant.completed`
- `tool.call.started`
- `tool.call.output`
- `tool.call.completed`
- `tool.call.failed`
- `approval.requested`
- `approval.resolved`
- `artifact.created`
- `memory.updated`
- `skill.loaded`
- `cron.job.created`
- `session.status.changed`
- `error`

Every event should include:

```json
{
  "id": "evt_...",
  "sessionId": "...",
  "timestamp": "...",
  "type": "tool.call.started",
  "payload": {}
}
```

### 8.5 Approvals

Endpoints:

- `GET /approvals/pending`
- `GET /approvals/{approvalId}`
- `POST /approvals/{approvalId}/approve`
- `POST /approvals/{approvalId}/deny`
- `POST /approvals/{approvalId}/modify-and-approve`

Approval object:

```json
{
  "id": "approval_...",
  "sessionId": "...",
  "kind": "terminal|file_write|file_delete|connector_write|browser_action|memory_write",
  "risk": "low|medium|high|critical",
  "title": "Hermes wants to send an email",
  "summary": "Send email to jane@example.com",
  "details": {
    "destination": "jane@example.com",
    "subject": "...",
    "bodyPreview": "..."
  },
  "rawAction": {},
  "policyReason": "External write requires approval",
  "createdAt": "..."
}
```

### 8.6 Tools/toolsets

Endpoints:

- `GET /tools`
- `GET /toolsets`
- `PATCH /toolsets/{name}`
- `POST /tools/{toolName}/test`

Tool capability object:

```json
{
  "name": "terminal",
  "toolset": "terminal",
  "enabled": true,
  "requiresApprovalFor": ["destructive_commands"],
  "available": true,
  "missingRequirements": []
}
```

### 8.7 Skills

Endpoints:

- `GET /skills`
- `GET /skills/{name}`
- `POST /skills/install`
- `PATCH /skills/{name}`
- `POST /skills/{name}/load`
- `POST /skills/{name}/test`
- `POST /skills/create-from-session`

### 8.8 Memory

Endpoints:

- `GET /memory/status`
- `GET /memory/user-profile`
- `GET /memory/notes`
- `POST /memory/notes`
- `PATCH /memory/notes/{id}`
- `DELETE /memory/notes/{id}`
- `POST /memory/search`

### 8.9 Cron/automations

Endpoints:

- `GET /cron/jobs`
- `POST /cron/jobs`
- `GET /cron/jobs/{jobId}`
- `PATCH /cron/jobs/{jobId}`
- `POST /cron/jobs/{jobId}/run`
- `POST /cron/jobs/{jobId}/pause`
- `POST /cron/jobs/{jobId}/resume`
- `DELETE /cron/jobs/{jobId}`
- `GET /cron/jobs/{jobId}/runs`

### 8.10 Connectors

Endpoints:

- `GET /connectors`
- `GET /connectors/{connectorId}`
- `POST /connectors/{connectorId}/connect`
- `POST /connectors/{connectorId}/disconnect`
- `POST /connectors/{connectorId}/test`
- `GET /connectors/{connectorId}/capabilities`
- `PATCH /connectors/{connectorId}/policy`

Connector object:

```json
{
  "id": "github",
  "name": "GitHub",
  "status": "connected|not_connected|needs_reauth|config_required|error",
  "backend": "native_tool|mcp|oauth_broker|gateway|custom",
  "capabilities": [
    { "id": "github.read_issues", "mode": "read", "approvalRequired": false },
    { "id": "github.create_issue", "mode": "write", "approvalRequired": true }
  ],
  "requirements": [],
  "lastTest": {
    "status": "pass",
    "checkedAt": "..."
  }
}
```

---

## 9. Mac app UX architecture

### 9.1 Navigation model

Use a premium Mac three-pane pattern.

Left sidebar:

- New Chat
- Inbox / Today
- Sessions
- Automations
- Connectors
- Skills
- Memory
- Files / Projects
- Settings

Center content:

- active chat/task
- automation list/detail
- connector detail
- skill detail
- memory/settings page

Right inspector:

- current task status
- tool activity
- approvals
- artifacts
- logs
- context/attachments

### 9.2 Main surfaces

1. Chat / Task Workspace
2. Automations
3. Connectors
4. Skills
5. Memory
6. Sessions / History
7. Projects / Workdirs
8. Settings / Preferences
9. Action Center
10. Menu Bar Quick Prompt

---

## 10. Detailed feature spec

## 10.1 First-run onboarding

Goal: get user from install to useful agent in under 5 minutes.

Steps:

1. Welcome screen.
2. Choose Hermes engine mode:
   - use installed Hermes
   - install/manage bundled Hermes
   - advanced: custom Hermes daemon URL
3. Check Hermes health.
4. Choose model/provider:
   - existing Hermes config
   - OpenRouter
   - Anthropic
   - OpenAI/Codex OAuth if supported
   - local model endpoint
5. Select default profile.
6. Choose default permissions:
   - safe mode: ask before file/terminal/external writes
   - developer mode: fewer prompts in selected project folders
7. Optional: enable menu bar/global hotkey.
8. Land in New Chat.

Acceptance criteria:

- User can complete onboarding without terminal.
- If Hermes missing, app explains install options.
- If provider missing, app gives clear setup path.
- No secrets shown in logs or UI.

## 10.2 Chat / Task Workspace

Capabilities:

- create new session
- send message
- stream assistant response
- attach files/folders/screenshots/images
- choose project/workdir
- choose model/profile/skills for session
- show tool activity inline
- show approvals as native sheets
- stop/retry/branch session
- save artifacts
- copy/share final answer

UI requirements:

- Clean composer at bottom.
- Streaming text feels smooth.
- Tool calls are collapsed by default with expandable details.
- Approvals are impossible to miss.
- Long tasks show status/progress.
- Errors show clear next steps.

Acceptance criteria:

- Chat works with a plain text prompt.
- Tool calls stream as events.
- User can stop a running session.
- Session persists after app restart.
- Attachments appear in context and are sent to Hermes.

## 10.3 Action Evidence / Activity Inspector

Goal: users can trust what Hermes did.

Show:

- commands run
- files read/written
- browser pages opened
- connector actions proposed/executed
- approvals requested/resolved
- artifacts created
- errors

Modes:

- summary timeline
- detailed JSON/raw view for power users
- export evidence

Acceptance criteria:

- Every tool call from stream appears in inspector.
- Mutating actions show approval/evidence state.
- Failed actions show error and retry path.

## 10.4 Approvals

Approval types:

- terminal command
- file write/delete/outside-workspace access
- connector write
- browser action
- memory write/delete
- automation creation with external writes
- cron job with future external side effects

Native sheet content:

- title
- exact action
- destination/path/command
- risk level
- reason approval is required
- preview/diff when available
- approve
- deny
- modify-and-approve where supported

Acceptance criteria:

- User can approve or deny without leaving current session.
- Approval event resolves in Hermes daemon.
- Denied action does not execute.
- Approved action produces action evidence.

## 10.5 Automations

Automations are Hermes cron jobs with a Mac-native builder.

Surfaces:

- automation list
- automation detail
- natural-language create flow
- schedule editor
- test run
- run history
- pause/resume/delete
- failure notifications

Create flow:

1. User types automation idea.
2. Hermes drafts automation:
   - name
   - schedule
   - prompt
   - required tools/connectors
   - delivery target
   - safety policy
3. User reviews.
4. App validates requirements.
5. User saves disabled or active.
6. Optional test run.

Automation object:

- id
- name
- schedule
- prompt
- skills
- enabled toolsets
- connectors required
- approval policy
- delivery target
- next run
- last run
- status

Acceptance criteria:

- User can create a simple daily automation.
- User can test-run automation.
- User can pause/resume/delete.
- Run history is visible.
- External-write automations require explicit safety policy/approval.

## 10.6 Connectors

Goal: Handle-like connector experience, powered by Hermes tools/MCP/OAuth.

Connector detail page:

- status
- backend type
- connected account
- capabilities
- required permissions
- safety policy
- test connection
- example prompts
- example automations
- recent actions
- troubleshooting

Connector statuses:

- Not Connected
- Connected
- Needs Reauth
- Config Required
- Missing Tool
- Missing Scope
- Error
- Read Only
- Write Capable

Connector backend types:

1. Hermes native tool
2. MCP server
3. OAuth broker
4. Gateway platform
5. Local app integration
6. Custom script/tool

Initial connector catalog:

Local/system:

- Files/Folders
- Terminal
- Browser
- Clipboard
- Screenshots
- Apple Notes
- Apple Reminders
- Calendar local/system if available
- Obsidian

Developer/productivity:

- GitHub
- Linear
- Notion
- Airtable
- Google Workspace
- Gmail
- Google Calendar
- Google Drive
- Google Sheets
- Slack
- Discord
- Telegram
- Vercel
- Cloudflare

Media/other:

- Spotify
- YouTube transcript/search
- Maps

Safety defaults:

- read-only after connect is allowed
- all external writes require approval
- delete/destructive actions require approval every time
- user can never globally approve destructive actions silently in v1

Acceptance criteria:

- Connector list truthfully reports configured/available/missing states.
- Test connection gives actionable result.
- Write capability is not shown unless tool exists and auth/scopes are valid.
- Connector write requests produce approval sheet.

## 10.7 Skills

Skills UI:

- installed skills
- available/search/browse if registry available
- skill detail
- enable/disable per profile/platform
- load into current session
- create skill from session/workflow
- update/check skills

Acceptance criteria:

- User can view installed skills.
- User can load a skill into active session.
- User can enable/disable skill for Desktop profile.
- Create-from-session produces a draft skill for review.

## 10.8 Memory

Memory UI:

- memory status
- user profile facts
- environment notes
- add/edit/delete memory
- search memories
- show memory source/history where available
- privacy controls

Acceptance criteria:

- User can inspect what Hermes remembers.
- User can delete a memory.
- User can toggle memory provider/status where supported.
- Secret/PII safety warnings are visible.

## 10.9 Sessions / History

Features:

- list sessions
- search sessions
- resume session
- rename
- delete/archive
- branch
- export transcript
- filter by project/profile/date

Acceptance criteria:

- Session list matches Hermes daemon sessions.
- Resume reopens conversation and can continue.
- Search works across titles/content if Hermes supports it.

## 10.10 Projects / Workdirs

Features:

- define trusted project folders
- open project chat
- attach repo context
- choose default tool policy per project
- show recent sessions per project
- optional git status summary

Acceptance criteria:

- User can select a project folder via native file picker.
- Hermes receives workdir for project sessions.
- File/terminal approvals reflect project trust boundary.

## 10.11 Settings / Preferences

Native Preferences window tabs:

- General
- Hermes Engine
- Models/Providers
- Tools
- Connectors
- Skills
- Memory
- Automations
- Voice
- Browser
- Security & Privacy
- Advanced

Settings storage:

- app UI preferences in app container
- Hermes config changes through Hermes API/CLI
- secrets in Keychain or Hermes credential store, never plaintext UI storage

Acceptance criteria:

- User can view Hermes config safely.
- Provider secrets are masked.
- Changes requiring restart say so.

## 10.12 Menu bar and global hotkey

Features:

- menu bar icon
- quick prompt
- recent sessions
- running tasks
- pending approvals
- pause/resume automations
- global hotkey to open quick prompt

Acceptance criteria:

- Global hotkey opens quick prompt.
- Quick prompt can send a message to new/current session.
- Pending approval count visible.

## 10.13 Native notifications

Notification types:

- task completed
- task failed
- approval needed
- automation run completed
- connector needs reauth
- daemon error

Acceptance criteria:

- User grants/denies notification permission gracefully.
- Clicking notification opens relevant session/job.

## 10.14 Voice

Features:

- push-to-talk
- voice message to Hermes STT
- TTS response optional
- voice settings

Acceptance criteria:

- Voice input uses Hermes STT provider or Mac dictation path by design.
- User can disable voice completely.
- No recording without visible active state.

## 10.15 Browser/computer-use UI

Features:

- show browser session status
- open browser view/screenshot when available
- approval for risky browser actions
- page screenshots/artifacts

Acceptance criteria:

- Browser actions appear in action inspector.
- Risky browser actions require approval.

---

## 11. Data model in Swift app

Use Swift models matching API objects.

Core models:

- `HermesSession`
- `HermesMessage`
- `HermesEvent`
- `ToolCall`
- `ApprovalRequest`
- `Artifact`
- `AutomationJob`
- `AutomationRun`
- `Connector`
- `ConnectorCapability`
- `Skill`
- `MemoryItem`
- `HermesProfile`
- `ProjectFolder`
- `AppPreference`

Persistence:

- SwiftData or SQLite for app-local UI cache.
- Do not treat cache as source of truth for Hermes sessions.
- Use Keychain for daemon tokens/provider credentials if app-owned.

---

## 12. Security and privacy

### 12.1 Secrets

- Store app-owned secrets in Keychain.
- Prefer Hermes credential store for Hermes-owned provider keys.
- Never print secrets in logs.
- Mask all tokens in UI.

### 12.2 Local daemon security

- Bind localhost only.
- Require token.
- Rotate token on request.
- Show daemon access status.

### 12.3 Permissions

Mac app permissions:

- files/folders via security-scoped bookmarks when sandboxed
- microphone for voice
- screen recording for screenshots/computer use if needed
- notifications
- accessibility only if global computer control features require it

### 12.4 Action safety

Require approval for:

- external writes
- destructive file ops
- shell commands classified risky
- browser actions that submit/checkout/purchase/login or mutate state
- memory writes with sensitive-looking content
- automations that can mutate external systems

---

## 13. Design direction

Visual style:

- premium native Mac utility
- clean, calm, low chrome
- SF Pro typography
- tasteful translucency only where useful
- native sidebar/list/detail patterns
- high contrast dark/light modes
- keyboard-first
- no SaaS-dashboard clutter

Layout inspirations:

- Xcode navigator/editor/inspector, but simpler
- Linear-level polish
- Raycast speed
- Arc/ChatGPT Desktop simplicity
- Apple Notes/Reminders native clarity

Core design tokens:

- macOS system colors where possible
- custom accent color optional
- status colors semantically consistent
- avoid over-custom titlebars unless quality is high

---

## 14. Quality bar

Every feature needs:

- unit tests for client models/API parsing
- mocked API tests for Swift services
- UI tests for critical flows
- Hermes daemon contract tests
- manual Mac QA checklist
- screenshots for visual regressions

Do not declare done unless:

- app builds with xcodebuild
- tests pass
- no obvious memory leaks/hanging streams
- app relaunch preserves expected state
- pending approvals cannot be lost silently
- connector capabilities are truthful

---

## 15. Milestone plan

## M0 — Architecture spike and API contract

Goal: prove SwiftUI app can communicate with Hermes daemon.

Tasks:

- inspect current Hermes API/gateway capabilities
- define desktop API contract
- add minimal daemon endpoint if needed
- create Swift Package/Xcode app skeleton
- implement health check client
- app shows Hermes status/version/profile

Exit criteria:

- macOS app launches
- Hermes daemon starts or is detected
- `/health` visible in UI
- documented API contract checked in

Recommended agent:

- Claude Code for Hermes architecture/API work
- Codex for Swift skeleton and focused endpoint tests

## M1 — Native chat MVP

Goal: basic chat with streaming.

Features:

- new session
- send message
- stream response
- stop session
- session list
- basic errors

Exit criteria:

- user can chat with Hermes from Swift app
- session persists and resumes
- stream events render smoothly

## M2 — Tool activity and approvals

Goal: safe agent work visibility.

Features:

- tool timeline
- approval sheets
- approve/deny
- artifact list
- action inspector

Exit criteria:

- dangerous command approval appears natively
- denial prevents action
- approved safe test action executes and shows evidence

## M3 — Settings, profiles, models, tools

Goal: one-stop configuration.

Features:

- native preferences
- profiles
- model/provider display/change
- toolsets enable/disable
- daemon logs/status

Exit criteria:

- app can read/update Hermes config where supported
- restart-required changes are clear

## M4 — Automations

Goal: natural-language automation setup and management.

Features:

- list cron jobs
- create job
- schedule editor
- test run
- run history
- pause/resume/delete
- notifications

Exit criteria:

- user can create/test/pause an automation from app

## M5 — Connectors

Goal: Handle-like connector manager.

Features:

- connector catalog
- status/capabilities
- setup/test connection
- policy controls
- recent actions
- example prompts/automations

Exit criteria:

- at least Files, Terminal, Browser, GitHub, Apple Reminders/Notes, Obsidian shown truthfully
- write actions approval-gated

## M6 — Skills and memory

Goal: manage Hermes intelligence.

Features:

- skills list/detail/load/enable
- create skill from session draft
- memory inspect/search/edit/delete

Exit criteria:

- user can load a skill and inspect memory from app

## M7 — Mac-native power features

Goal: feels like a real Mac productivity app.

Features:

- menu bar
- global hotkey
- quick prompt
- notifications
- drag/drop files
- screenshot to Hermes
- Finder integration draft
- voice input

Exit criteria:

- global hotkey and quick prompt work reliably

## M8 — Packaging and updater

Goal: distributable app.

Features:

- app icon
- app bundle
- bundled or detected Hermes engine strategy
- updater decision
- signing/notarization
- crash/log collection

Exit criteria:

- installable `.app`/DMG build
- signed/notarized when credentials available

## M9 — Beta QA and polish

Goal: high-quality dogfood release.

Features:

- full UI polish
- accessibility
- keyboard shortcuts
- onboarding refinements
- failure-state hardening
- docs

Exit criteria:

- end-to-end dogfood checklist passes
- no P0/P1 issues

---

## 16. Build-agent strategy

Do use Codex, but not as the only builder.

Recommended team:

- Hermes: product lead/orchestrator/spec owner/QA verifier
- Claude Code: architecture-heavy Hermes daemon/API design, SwiftUI architecture reviews, complex refactors
- Codex: focused implementation slices, tests, bug fixes, UI components, endpoint wiring
- Dedicated QA/browser/macOS tester: Xcode builds, app launch, UI tests, screenshots

### 16.1 What Codex is good for here

Use Codex for:

- creating SwiftUI screens from precise specs
- writing API client models/tests
- adding small Hermes daemon endpoints
- fixing compiler errors
- building UI tests
- implementing connector status pages
- adding focused automation CRUD flows

### 16.2 What not to give Codex as one task

Do not ask Codex:

- “Build the whole Hermes Desktop app.”
- “Convert Hermes to a Mac app.”
- “Implement all connectors.”

Instead, give it milestone/task prompts with exact files, acceptance criteria, and verification commands.

### 16.3 First Codex prompt after repo exists

```text
You are working in the Hermes Desktop repo. Build M0 only: a SwiftUI macOS app skeleton that connects to a local Hermes daemon health endpoint and renders status/version/profile. Do not implement chat yet. Add typed API client models, mock client tests, app shell, status screen, and README instructions. Run xcodebuild build/test and report results.
```

---

## 17. Repository plan

Proposed repo:

`/Users/perlantir/Projects/HermesDesktop`

Suggested structure:

```text
HermesDesktop/
  HermesDesktop.xcodeproj or Package.swift
  App/
    HermesDesktopApp.swift
    AppState.swift
  Sources/
    HermesDesktop/
      Features/
        Chat/
        Automations/
        Connectors/
        Skills/
        Memory/
        Settings/
        Approvals/
        MenuBar/
      Services/
        HermesAPIClient.swift
        HermesDaemonManager.swift
        KeychainStore.swift
        NotificationService.swift
      Models/
      DesignSystem/
  Tests/
    HermesDesktopTests/
    HermesDesktopUITests/
  Docs/
    HERMES_DESKTOP_FULL_BUILD_SPEC.md
    API_CONTRACT.md
    QA_CHECKLIST.md
  Scripts/
    build.sh
    test.sh
```

---

## 18. Open questions

1. Should Hermes Desktop be a private personal tool first, or designed for public distribution from day one?
2. Should the app bundle Hermes, use installed Hermes, or support both?
3. Should connector OAuth be direct, MCP-first, or broker-backed?
4. Should the first app be sandboxed? Sandboxing improves distribution but complicates local file/terminal control.
5. Should the UI call it Hermes Desktop, Handle Lite, or a new product name?
6. Should automations deliver to desktop notifications only, or also Telegram/email/etc. via Hermes gateway?
7. Should the app support multiple Hermes profiles at once?

---

## 19. Immediate next steps

1. Decide product name and repo location.
2. Inspect Hermes source/API/gateway to confirm current daemon capabilities.
3. Write `Docs/API_CONTRACT.md` for the initial daemon API.
4. Create SwiftUI macOS app skeleton.
5. Implement M0 health/status.
6. Use Codex for focused slices, with Hermes/Claude reviewing architecture.

---

## 20. Recommended answer to “Should we use Codex?”

Yes, but use Codex as an implementation worker, not the product architect.

Recommended workflow:

1. Hermes writes/maintains the spec and milestone prompts.
2. Codex implements one bounded milestone/task at a time.
3. Claude Code handles architecture-heavy daemon/API or SwiftUI design reviews when useful.
4. Hermes verifies builds/tests/QA evidence before moving on.

This avoids the common failure mode where a coding agent creates a large, fragile app skeleton without a stable engine boundary.
