# Hermes Desktop — Full Product Design Brief

Date: 2026-05-09  
Audience: Product/UI designer creating full SwiftUI macOS app designs  
Product: Hermes Desktop  
Goal: Premium Mac-native UI for Hermes Agent — chat, automations, connectors, approvals, skills, memory, settings

---

## 1. One-line product summary

Hermes Desktop is a clean Mac-native AI operator: chat with Hermes, connect tools, approve actions, and create automations from one polished desktop app.

---

## 2. Design goal

Design the full Mac app experience, not only an MVP.

The app should feel:

- native to macOS
- premium and calm
- powerful but not cluttered
- more like Raycast / Linear / Apple productivity software than a web dashboard
- safe and trustworthy when the agent touches files, terminal, browser, or external accounts

The UI should make advanced Hermes features feel simple:

- tools
- skills
- connectors
- memory
- cron automations
- approvals
- sessions
- local models/cloud models

---

## 3. Core product concept

Hermes is the engine. The SwiftUI Mac app is the beautiful control center.

The user should not feel like they are configuring a developer CLI. They should feel like they have a personal Mac-native AI operator that can:

1. answer questions
2. work on files/projects
3. use tools/connectors
4. ask before risky actions
5. remember useful context
6. run scheduled automations
7. show exactly what it did

---

## 4. Design principles

### 4.1 Native first

Use macOS-native patterns:

- sidebar navigation
- toolbar/titlebar actions
- native sheets
- preferences window
- context menus
- keyboard shortcuts
- file pickers
- notifications
- menu bar utility

### 4.2 Simple surface, powerful inspector

Main chat should stay clean. Advanced detail should live in inspector panels:

- tool activity
- approvals
- artifacts
- logs
- context

### 4.3 Trust through visibility

Whenever Hermes acts, the user should see:

- what it wants to do
- why
- where
- risk level
- exact command/content/destination
- result/evidence

### 4.4 No fake magic

Connector and automation states must be clear:

- connected
- not connected
- missing scope
- read-only
- write-capable
- needs approval
- failed

### 4.5 Keyboard-first but approachable

Power users need speed. Normal users need clarity.

Support:

- Cmd+N new chat
- Cmd+K command palette
- Cmd+, settings
- Cmd+Enter send/run
- global hotkey quick prompt

---

## 5. Suggested visual direction

Designer can choose final style, but recommended direction:

- Apple-native foundation
- Linear-level precision
- Raycast-like speed/polish
- subtle technical confidence from developer tools
- no generic SaaS card clutter
- no loud gradients unless used very sparingly

### 5.1 Mood words

- calm
- precise
- intelligent
- safe
- premium
- fast
- native
- focused

### 5.2 Avoid

- generic chatbot look
- web dashboard feel
- too many rounded cards
- AI purple gradient clichés
- fake metrics
- noisy icon grids
- huge empty hero areas
- cluttered developer-console UI by default

### 5.3 Modes

Design both:

- Dark mode primary
- Light mode secondary

---

## 6. App information architecture

Primary navigation should support these top-level areas:

1. Home / New Chat
2. Sessions / History
3. Automations
4. Connectors
5. Skills
6. Memory
7. Projects / Workspaces
8. Action Center
9. Settings / Preferences

Recommended layout:

- left sidebar: top-level navigation and recent sessions
- center pane: active content/chat/list/detail
- right inspector: context, tool activity, approvals, artifacts, metadata

The app should work well with the inspector hidden or visible.

---

## 7. Global shell screens/states

### 7.1 First-run onboarding

Purpose: get user connected to Hermes and ready to use the app.

Screens:

1. Welcome
2. Hermes engine setup
3. Model/provider setup
4. Permissions/safety defaults
5. Optional native features
6. Ready screen

#### 7.1.1 Welcome

Content:

- product name/logo placeholder
- one sentence: “Your Mac-native control center for Hermes Agent.”
- primary CTA: Get Started
- secondary: Use Existing Hermes Install

#### 7.1.2 Hermes Engine Setup

Options:

- Use installed Hermes
- Install/manage bundled Hermes
- Connect to custom local daemon

States:

- detected and healthy
- not found
- version outdated
- daemon not running
- custom URL invalid

#### 7.1.3 Model/Provider Setup

Show provider options:

- use existing Hermes config
- OpenRouter
- Anthropic
- OpenAI/Codex
- local model endpoint
- custom provider

Need states:

- connected
- missing API key/auth
- test failed
- key hidden/masked

#### 7.1.4 Permissions/Safety Defaults

Let user choose:

- Safe Mode: ask before file/terminal/external writes
- Developer Mode: trust selected project folders, still ask for destructive/external writes
- Custom

Show what Hermes can access.

#### 7.1.5 Native Features

Toggles:

- Menu bar icon
- Global hotkey
- Notifications
- Microphone/voice
- Screenshot/screen recording later

#### 7.1.6 Ready

CTA:

- Start New Chat
- Connect Tools
- Create Automation

---

## 8. Main app shell

### 8.1 Sidebar

Sections:

- New Chat button
- Today / Inbox
- Recent Sessions
- Automations
- Connectors
- Skills
- Memory
- Projects
- Action Center
- Settings

Sidebar detail:

- active selection
- running task indicator
- pending approval badge
- automation failure badge
- connector reauth badge

### 8.2 Toolbar

Contextual depending on page.

Common controls:

- sidebar toggle
- inspector toggle
- profile/model selector
- search / command palette
- new chat
- pending approval indicator

### 8.3 Right Inspector

Tabs or segmented sections:

- Activity
- Context
- Artifacts
- Approvals
- Details

Should be collapsible.

---

## 9. Home / Chat workspace

This is the core screen.

### 9.1 Empty state

Purpose: invite user to ask Hermes to do something.

Elements:

- centered composer or bottom composer
- suggested prompts grouped by category:
  - Work on a project
  - Research something
  - Automate a task
  - Connect a tool
  - Review files
- active model/profile indicator
- selected project/workdir indicator if any

Example prompts:

- “Summarize this project and suggest next steps.”
- “Check my open GitHub PRs every weekday morning.”
- “Draft a reply to this email, but ask before sending.”
- “Turn this workflow into a reusable skill.”

### 9.2 Active chat screen

Elements:

- message timeline
- user messages
- assistant messages
- streaming assistant state
- inline tool cards collapsed by default
- approval cards/sheets
- artifacts chips
- composer

Composer capabilities:

- text input
- attach file/folder
- screenshot button
- voice button
- project/workdir picker
- skill picker
- tool/profile/model selector
- send button

### 9.3 Tool call card

Collapsed view:

- icon/type
- title
- status
- duration
- brief summary

Expanded view:

- command/action
- input args
- output preview
- errors
- copy button
- open artifact button

Tool card statuses:

- queued
- running
- waiting for approval
- completed
- failed
- denied
- skipped

### 9.4 Chat states to design

- empty
- streaming
- long-running task
- tool running
- approval needed
- stopped
- failed
- completed
- partial success
- offline/daemon disconnected
- model/provider error
- context too large

---

## 10. Approvals UX

Approvals are critical. They should feel native, clear, and safe.

### 10.1 Approval sheet

Use a native modal/sheet style.

Content:

- risk badge: Low / Medium / High / Critical
- action title
- plain-English summary
- exact target/destination/path/command
- preview/diff/content
- why approval is needed
- buttons:
  - Deny
  - Modify
  - Approve Once

Optional future button:

- Always allow for this project/session, only for low-risk safe scopes

### 10.2 Approval types to design

1. Terminal command
2. File write
3. File delete
4. External connector write
5. Browser submit/click/purchase-like action
6. Memory save/delete
7. Automation with future side effects

### 10.3 Approval card in chat

If not full modal, inline card should show:

- pending action
- risk
- approve/deny buttons
- view details

### 10.4 Approval history

Action Center should show all approval decisions.

---

## 11. Action Center

Purpose: global view of what Hermes is doing or waiting on.

Sections:

- Pending approvals
- Running tasks
- Failed tasks
- Recent actions
- Connector issues
- Automation failures

Each item:

- source session/job
- status
- timestamp
- action type
- quick action

States:

- empty: “No pending actions”
- pending approvals
- failures
- all clear

---

## 12. Sessions / History

### 12.1 Session list

Filters:

- All
- Today
- This week
- By project
- By profile
- Has artifacts
- Has errors
- Has approvals

Each row:

- title
- preview
- timestamp
- model/profile
- project/workdir
- status
- badges for tools/artifacts/approvals

### 12.2 Session detail

Reuse chat workspace but read/resume mode.

Actions:

- resume
- rename
- branch
- export
- delete/archive

### 12.3 Search state

Search sessions by:

- title
- content
- project
- tool/action

---

## 13. Automations

Automations are scheduled Hermes jobs.

### 13.1 Automation dashboard

Show:

- active automations
- paused automations
- failed/needs attention
- recent runs
- create button

Each card/row:

- name
- schedule
- next run
- last run status
- required tools/connectors
- output destination
- pause/resume
- run now

### 13.2 Empty state

Explain automations simply:

“Ask Hermes to do recurring work on a schedule.”

Examples:

- “Every morning, summarize my unread important emails.”
- “Every Friday, review open GitHub PRs.”
- “Every 2 hours, check whether my app deployment is healthy.”

### 13.3 Create automation — conversational builder

Flow:

1. User describes automation
2. Hermes drafts configuration
3. User reviews schedule/tools/connectors/safety
4. User tests it
5. User saves active or paused

Designer should create this as a guided wizard/chat hybrid.

Draft review fields:

- automation name
- natural language goal
- schedule
- timezone
- prompt
- skills loaded
- toolsets enabled
- connectors required
- output/delivery target
- approval policy
- failure behavior

### 13.4 Schedule editor

Support:

- plain English schedule
- presets
- cron advanced mode
- timezone
- repeat count/end date optional

### 13.5 Automation detail

Tabs/sections:

- Overview
- Runs
- Configuration
- Permissions
- Output
- Logs

Actions:

- Run now
- Pause/resume
- Edit
- Duplicate
- Delete

### 13.6 Run history

Each run:

- status
- start/end time
- duration
- output summary
- errors
- artifacts
- tool usage

---

## 14. Connectors

Handle-like connector manager, but powered by Hermes tools/MCP/OAuth.

### 14.1 Connector catalog

Categories:

- Local Mac
- Developer
- Productivity
- Communication
- Knowledge bases
- Cloud/deploy
- Media/research

Catalog cards:

- icon
- name
- short description
- status badge
- capability badges: Read, Write, Automate
- setup requirement

Statuses:

- Connected
- Not Connected
- Needs Reauth
- Missing Scope
- Read Only
- Write Capable
- Config Required
- Unavailable
- Error

### 14.2 Connector detail page

Sections:

- Header: name/status/account
- Capabilities
- Permissions/scopes
- Safety policy
- Test connection
- Example prompts
- Example automations
- Recent actions
- Troubleshooting

### 14.3 Connector capabilities

Each capability should show:

- read/write/destructive classification
- approval requirement
- required scope/tool
- available/unavailable

Example GitHub:

- Read issues: available, no approval
- Create issue: available, approval required
- Comment on PR: available, approval required
- Merge PR: high risk, approval required every time

### 14.4 Connector setup flow

Generic flow:

1. Select connector
2. Explain what Hermes can do
3. Choose auth method/tool backend
4. Connect/sign in/configure
5. Test connection
6. Review capabilities and safety rules
7. Done

### 14.5 Initial connectors to design

Local/Mac:

- Files/Folders
- Terminal
- Browser
- Clipboard
- Screenshot/Screen
- Apple Notes
- Apple Reminders
- Obsidian

Developer/productivity:

- GitHub
- Slack
- Gmail
- Google Calendar
- Google Drive
- Google Sheets
- Notion
- Linear
- Airtable
- Discord
- Telegram
- Vercel
- Cloudflare

### 14.6 Connector error states

Design states for:

- auth failed
- token expired
- missing scope
- connected but read-only
- write tool unavailable
- rate limited
- permission denied
- API error
- tool not installed

---

## 15. Skills

Skills are reusable procedures Hermes can load.

### 15.1 Skills library

Views:

- Installed
- Recommended
- Available/Browse
- Recently used
- Created by me

Skill card:

- name
- description
- category/tags
- status installed/enabled
- last used
- compatible surfaces: chat/automation/connector

### 15.2 Skill detail

Sections:

- description
- when to use
- instructions preview
- linked files/assets
- required tools/env
- enable/disable
- load into current chat
- update/check
- delete/uninstall

### 15.3 Create skill from session

Flow:

1. Select session/workflow
2. Hermes drafts skill
3. User reviews/edits
4. Save/install

Designer should include a review/editor screen.

---

## 16. Memory

Memory lets users inspect and manage what Hermes remembers.

### 16.1 Memory dashboard

Sections:

- User profile
- Environment notes
- Project conventions
- Skills/procedural memory link
- Recent memory changes

### 16.2 Memory item design

Each memory item:

- content
- type/category
- created/updated
- source session if available
- edit/delete

### 16.3 Memory states

- memory enabled
- memory disabled
- provider not configured
- sync/error state
- search results
- empty state

### 16.4 Privacy controls

Show:

- what is remembered
- ability to delete
- warning for secrets/PII

---

## 17. Projects / Workspaces

Projects are local folders/repos Hermes can work inside.

### 17.1 Project list

Each project:

- name
- path
- recent sessions
- git status summary optional
- trusted/untrusted badge
- default profile/model/tools

### 17.2 Project detail

Sections:

- Overview
- Recent sessions
- Automations tied to project
- Files/context
- Tool permissions
- Git status
- Settings

### 17.3 Add project flow

Use native folder picker.

Ask:

- trust this folder?
- default tool policy?
- include hidden files?
- allow terminal commands in this folder?

---

## 18. Settings / Preferences

Native macOS Preferences window.

Tabs:

1. General
2. Hermes Engine
3. Models & Providers
4. Profiles
5. Tools & Permissions
6. Connectors
7. Automations
8. Skills
9. Memory
10. Voice
11. Browser
12. Notifications
13. Security & Privacy
14. Advanced

### 18.1 General

- launch at login
- menu bar icon
- global hotkey
- theme: system/light/dark
- default landing page

### 18.2 Hermes Engine

- engine mode: installed/bundled/custom
- version
- daemon status
- start/stop/restart
- logs
- update check

### 18.3 Models & Providers

- default provider/model
- configured providers
- add provider
- test provider
- masked keys/auth status
- local model endpoint

### 18.4 Profiles

- list profiles
- create/switch/delete
- default profile

### 18.5 Tools & Permissions

- enable/disable toolsets
- approval policy
- trusted project folders
- dangerous command policy

### 18.6 Security & Privacy

- secret redaction
- PII redaction if available
- memory enable/disable
- logs/data retention
- delete local data

---

## 19. Menu bar / Quick Prompt

### 19.1 Menu bar popover

Content:

- quick prompt input
- pending approvals count
- running tasks
- recent sessions
- quick actions:
  - New Chat
  - Screenshot to Hermes
  - Summarize Clipboard
  - Create Automation

### 19.2 Global quick prompt

Lightweight floating window.

Actions:

- send to new chat
- send to current session
- attach clipboard/selection/screenshot
- choose project

---

## 20. Notifications

Design notification behavior for:

- task completed
- task failed
- approval needed
- automation completed
- automation failed
- connector needs reauth
- daemon disconnected

Clicking notification should deep-link to relevant screen.

---

## 21. Voice

Voice surfaces:

- composer mic button
- push-to-talk overlay
- voice settings
- recording active indicator
- transcription confirmation
- optional TTS response control

States:

- permission not granted
- recording
- transcribing
- failed transcription
- voice disabled

---

## 22. Browser/computer-use visibility

If Hermes uses browser/computer tools, UI should show:

- active browser session
- current URL/page title if available
- screenshot/artifact preview
- action log
- approval for risky interactions

Do not make browser/computer-use feel invisible or spooky.

---

## 23. Empty/loading/error states required

Designer should include reusable patterns for:

### Empty states

- no sessions
- no automations
- no connectors connected
- no skills installed
- no memory
- no projects
- no pending approvals

### Loading states

- daemon connecting
- provider testing
- connector testing
- session loading
- automation run loading
- streaming response

### Error states

- daemon offline
- Hermes outdated
- model unavailable
- auth failed
- connector missing scope
- tool unavailable
- permission denied
- automation failed
- task failed
- unknown error with logs link

---

## 24. Critical modals/sheets to design

1. New Chat / command palette
2. Approval: terminal command
3. Approval: file write diff
4. Approval: connector write/send
5. Connect account OAuth/config sheet
6. Create automation review sheet
7. Add project folder/trust sheet
8. Provider API key/auth sheet
9. Skill creation review sheet
10. Delete/destructive confirmation

---

## 25. Component inventory

Design reusable components:

- Sidebar item
- Session row
- Message bubble/block
- Tool call card
- Approval card
- Artifact chip/card
- Automation card/row
- Connector card
- Capability row
- Skill card
- Memory item row
- Project row
- Status badge
- Risk badge
- Empty state block
- Inspector panel
- Settings row
- Native sheet template
- Command palette row
- Toast/banner
- Error callout

---

## 26. Status/risk taxonomy

### 26.1 Task statuses

- Idle
- Running
- Waiting for approval
- Waiting for user input
- Completed
- Failed
- Stopped
- Cancelled
- Partial success

### 26.2 Risk levels

- Low
- Medium
- High
- Critical

### 26.3 Connector capability modes

- Read
- Write
- Destructive
- Automation-safe
- Approval-required

---

## 27. Design deliverables requested

Please produce designs for:

### Must-have full app screens

1. First-run onboarding: welcome
2. First-run onboarding: Hermes engine setup
3. First-run onboarding: model/provider setup
4. First-run onboarding: safety/permissions
5. Main app empty Home/New Chat
6. Active Chat with streaming response
7. Chat with tool activity visible
8. Chat with pending approval
9. Right inspector: Activity
10. Right inspector: Artifacts
11. Action Center
12. Sessions/History list
13. Session detail/resume
14. Automations dashboard
15. Create Automation conversational builder
16. Automation review/config screen
17. Automation detail with run history
18. Connectors catalog
19. Connector detail: connected/write capable
20. Connector detail: missing scope/error
21. Connector setup flow
22. Skills library
23. Skill detail
24. Create Skill from session review
25. Memory dashboard
26. Memory item edit/delete
27. Projects list
28. Project detail/settings
29. Settings: General
30. Settings: Hermes Engine
31. Settings: Models & Providers
32. Settings: Tools & Permissions
33. Settings: Security & Privacy
34. Menu bar popover
35. Global quick prompt
36. Notification/deep-link behavior mock

### Required modal/sheet designs

1. Approval terminal command
2. Approval file write diff
3. Approval connector send/post
4. Connect provider/API key
5. Connect OAuth account
6. Add project/trust folder
7. Create automation final review
8. Destructive delete confirmation
9. Daemon offline/reconnect
10. Skill draft review

### Required responsive/window states

Design at least:

- compact window
- standard desktop window
- wide window with inspector
- dark mode
- light mode

---

## 28. Acceptance criteria for design package

Design is complete if:

- all major product areas are represented
- empty/loading/error states exist
- dangerous action approval is crystal clear
- connector capabilities/statuses are truthful and legible
- automation creation feels easy and inspectable
- app feels Mac-native, not like a web dashboard
- design supports both simple users and power users
- component system is reusable enough for SwiftUI implementation
- dark and light modes are addressed
- handoff includes spacing/type/color/component notes

---

## 29. Notes for designer

Nick will provide the exact design style/taste references separately.

Use this document to know what needs to be designed. Do not shrink scope to only chat. The full app includes automations, connectors, approvals, skills, memory, sessions, projects, settings, and Mac-native quick access.

Prioritize visual polish on:

1. main chat/task workspace
2. approval UX
3. automation builder
4. connector manager
5. settings/preferences
6. menu bar/global quick prompt

---

## 30. Implementation handoff expectation

The final design package should allow engineering to build the SwiftUI app in phases:

- M0 app shell / daemon status
- M1 chat
- M2 approvals/action evidence
- M3 settings/models/tools
- M4 automations
- M5 connectors
- M6 skills/memory
- M7 menu bar/global hotkey/native integrations

Please organize designs and components so screens map cleanly to these milestones.
