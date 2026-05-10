# Diak Connector Architecture Decision

Updated: 2026-05-09

## Decision

Diak will use a provider-agnostic connector architecture with **Composio as the first external connector provider**, plus native connector providers for high-control integrations.

The product must not couple UI, approval policy, automation policy, or audit logs directly to Composio. Diak owns the safety layer and internal domain model.

## Product Direction

- Public product name: **Diak**.
- Logo/brand assets will be supplied later.
- Go public only after testing and safety/automation behavior are credible.
- Users should be able to choose strict approvals or opt into more autonomous/fun operation.

## Provider Strategy

### Composio-first

Use Composio first for broad SaaS coverage and fast OAuth/connect flows.

Good candidates:

- Notion
- Slack
- Gmail / Google Workspace
- GitHub
- Linear / Jira / Asana
- Calendar and common productivity connectors

### Native/high-control connectors

Prefer native/custom provider implementations where Diak needs tighter UX, scoped risk handling, or non-standard auth.

Initial native/custom candidates:

- Telegram
- Cloudflare
- agentmail.to
- local machine tools
- files, shell, browser, local apps

### Future fallback/secondary providers

Keep the interface open to add:

- Nango for OAuth/token management if Diak wants to own the full action layer.
- Pipedream Connect for broad workflow/action catalog if needed.
- Direct OAuth for critical connectors where native quality matters.

## Required Internal Abstractions

Diak should model connectors through internal protocols/entities such as:

- `ConnectorProvider`
- `Connector`
- `Connection`
- `ConnectorAction`
- `ApprovalPolicy`
- `ActionRisk`
- `ExecutionResult`
- `AuditLogEntry`

No app screen should call Composio-specific SDK/API objects directly.

## Approval Policy Direction

Diak should support flexible user-configurable approval modes:

1. **Strict** — ask before every connector action.
2. **Safe default** — allow reads after connection, ask before writes/sends/destructive actions.
3. **Risk-based** — ask only for risky actions.
4. **Autonomous** — act automatically unless blocked by global/user/connector/action policy.

Even in autonomous mode, Diak should treat the following as high risk by default:

- billing/spend changes
- destructive deletes
- public posts
- external messages/emails
- DNS/security changes
- production infrastructure changes
- large bulk edits
- inviting users or changing permissions

## M2/M3 Boundary

M2 remains approvals/action evidence only. It may include connector-send approval previews, but must not implement real OAuth or connector writes.

M3 or later should implement the connector foundation:

1. Connector registry UI.
2. Provider-agnostic connection model.
3. Composio provider skeleton.
4. One Composio-backed connector proof of concept, likely Notion.
5. One native/custom connector proof of concept, likely Telegram, Cloudflare, or agentmail.to.
6. Approval-policy enforcement before action execution.
7. Audit log for every connector action.

## Acceptance Criteria For Connector Foundation

- UI can display available connectors without knowing provider-specific details.
- User can start a connect flow from a connector row/card.
- App can represent connection states: disconnected, connecting, connected, expired, revoked, error.
- Every action has risk metadata and required scopes.
- Approval policy is checked before any write/send/destructive action.
- Audit log is recorded for every attempted action, approved or denied.
- Provider-specific errors are translated into user-readable Diak errors.
- No secrets are logged or committed.
