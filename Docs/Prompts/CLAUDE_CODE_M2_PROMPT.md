# Claude Code Prompt — Hermes Desktop M2

Copy/paste/run this from the Hermes Desktop repo root.

```text
You are working on Hermes Desktop at `/Users/perlantir/Projects/HermesDesktop`.

M0 and M1 are complete and verified locally:

- Latest relevant commit: `2c632a4` — `M1 sessions and chat foundation`
- `xcodebuild -list` shows scheme `HermesDesktop`.
- `xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build` succeeded.
- `xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test` succeeded with 24 tests, 0 failures.

Build M2 only: Approvals + action evidence with native safety UI.

Design/source references:

- `Docs/HERMES_DESKTOP_FULL_BUILD_SPEC.md`
- `Docs/HERMES_DESKTOP_DESIGN_BRIEF.md`
- `Docs/DESIGN_PACKAGE_REVIEW_AND_BUILD_HANDOFF.md`
- Design package: `Docs/DesignPackage/hermes_desktop_design_package/`
- M2 artboards:
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/08_08-chat-with-pending-approval.svg`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/09_09-right-inspector-activity.svg`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/10_10-right-inspector-artifacts.svg`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/11_11-action-center.svg`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/37_37-modal-approval-terminal-command.svg`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/38_38-modal-approval-file-write-diff.svg`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/39_39-modal-approval-connector-send-post.svg`
  - `Docs/DesignPackage/hermes_desktop_design_package/artboards/svg/52_52-empty-loading-error-states-matrix.svg`

M2 scope:

1. Add approval/action-evidence domain models at the API boundary:
   - `HermesApprovalRequest` with id, title, kind, status, risk, created/updated timestamps, session/task context, summary, requester/tool name.
   - approval kinds for terminal command, file write/diff, and connector send/post preview.
   - `HermesApprovalDecision` / status types for pending, approved, denied, expired/cancelled.
   - `HermesActionEvidence` / activity items with status, timestamp, actor, summary, artifact references.
   - Keep models tolerant of unknown enum values where appropriate.
2. Extend `HermesAPIClient` with safe approval/evidence methods only:
   - `pendingApprovals() async throws -> [HermesApprovalRequest]`
   - `approval(id:) async throws -> HermesApprovalRequest`
   - `decideApproval(id:decision:note:) async throws -> HermesApprovalRequest`
   - `actionEvidence(sessionID:) async throws -> [HermesActionEvidence]`
   - These are boundary methods; do not perform any real local shell execution or connector writes in the app.
3. Extend `MockHermesAPIClient` with deterministic sample data:
   - one pending terminal command approval
   - one pending file diff approval
   - one connector send/post approval preview
   - sample action evidence/artifact references
   - approval/deny transitions for tests.
4. Implement reusable design components:
   - `ApprovalCard`
   - `ApprovalSheet`
   - `CommandPreviewView`
   - `DiffPreviewView`
   - `ActionEvidenceRow` or equivalent
   - extend `RiskBadge`, `EmptyStateView`, `ErrorStateView` if needed.
5. Implement M2 screens/views:
   - chat/session surface can show pending approval card matching screen 08 direction
   - right inspector activity/evidence panes matching screens 09–10 direction
   - Action Center route matching screen 11 direction
   - modal/sheet shell for terminal command, file diff, and connector send/post approval previews matching screens 37–39 direction
   - empty/loading/error state usage from screen 52.
6. Wire navigation safely:
   - sidebar Action Center opens the approval/action list
   - approval cards can open a sheet
   - approving/denying updates mock state locally and visibly
   - no unsafe live writes; all decisions remain mocked/API-boundary calls for M2.
7. Tests:
   - decoding tests for approval/evidence models including unknown enum tolerance
   - mock API approval decision tests
   - view model tests for loading pending approvals, opening/closing sheet state, approving/denying, and error states
   - regression tests must keep M0/M1 green.

Constraints:

- M2 only.
- Do NOT implement real command execution, real connector writes, OAuth, automations, skills, memory, models/tools settings expansion, menu bar, global hotkey, or native integrations.
- Do NOT reimplement Hermes internals or local agent loops.
- Hermes Agent remains the external/updatable engine via API/daemon boundary.
- Approval UI must make risk and finality clear; destructive/write-capable decisions must not look casual.
- Do not add secrets.
- Do not shell out to destructive commands.
- Reuse existing M0/M1 architecture and components; avoid broad rewrites.
- Keep SwiftUI view logic thin; use view models/services for state and decisions.

Verification required before final report:

```bash
/opt/homebrew/bin/xcodegen generate
xcodebuild -list
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' -configuration Debug build
xcodebuild -scheme HermesDesktop -destination 'platform=macOS' test
git status --short
```

If your permission sandbox blocks xcodegen/xcodebuild, still make the code changes and report the exact commands; Hermes will run verification after you finish.

At the end, report:

1. What you built.
2. Files changed.
3. Exact verification commands/results or permission blockers.
4. Known risks.
5. Suggested M3 prompt for settings/models/tools.
```
