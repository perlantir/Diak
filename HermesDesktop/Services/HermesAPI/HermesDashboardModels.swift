import Foundation

// MARK: - Naming convention
//
// Hermes wire format is snake_case. The dashboard client decodes with
// `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`, which maps
// `session_id` → `sessionId`, `gateway_pid` → `gatewayPid`,
// `actual_cost_usd` → `actualCostUsd`, etc. Property names here intentionally
// follow that mapping (lowercase acronym style) so no per-type CodingKeys
// are needed and the wire format → Swift translation is mechanical and
// inspectable. Phase 0's `HermesSession` uses the alternate convention
// (uppercase acronyms + explicit CodingKeys); the two coexist by virtue of
// distinct type names.

// MARK: - Sessions

/// Single session record returned by `GET /api/sessions/{id}` and
/// `GET /api/sessions`. Source of truth: Phase 0.5 REALITY.md.
///
/// Most fields are optional because Hermes returns nulls for inactive
/// sessions, billing-not-applicable rows, etc. The decoder is permissive:
/// Hermes may add fields between versions and we don't want the desktop
/// app to refuse a session because one cost-tracking column was renamed.
public struct HermesDashboardSession: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let source: String?
    public let userId: String?
    public let model: String?
    public let systemPrompt: String?
    public let parentSessionId: String?
    public let startedAt: Date?
    public let endedAt: Date?
    public let endReason: String?
    public let messageCount: Int?
    public let toolCallCount: Int?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cacheReadTokens: Int?
    public let cacheWriteTokens: Int?
    public let reasoningTokens: Int?
    public let billingProvider: String?
    public let billingBaseUrl: String?
    public let billingMode: String?
    public let estimatedCostUsd: Double?
    public let actualCostUsd: Double?
    public let costStatus: String?
    public let costSource: String?
    public let pricingVersion: String?
    public let title: String?
    public let apiCallCount: Int?
    public let lastActive: Date?
    public let preview: String?
    public let isActive: Bool?

    // Note: real Hermes also returns `model_config`. Its shape is union
    // (object | string | null) per session, which complicates strict
    // decoding and is not needed for Phase 1 display. Deliberately omitted
    // — Swift Codable silently ignores extra JSON fields, so any value
    // type is fine.
}

/// Paginated wrapper for `GET /api/sessions`. Hermes returns
/// `{sessions, total, limit, offset}` per Phase 0.5 REALITY.md.
public struct HermesDashboardSessionList: Codable, Sendable, Equatable {
    public let sessions: [HermesDashboardSession]
    public let total: Int
    public let limit: Int
    public let offset: Int
}

// MARK: - Messages

/// One message inside a Hermes-dashboard session. The shape is much wider
/// than the Phase 0 `HermesMessage` because Hermes captures reasoning
/// breadcrumbs and tool-call payloads on every assistant turn.
public struct HermesDashboardMessage: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: Int
    public let sessionId: String
    public let role: String
    public let content: String?
    public let toolCallId: String?
    public let toolCalls: [HermesDashboardToolCall]?
    public let toolName: String?
    public let timestamp: Double?
    public let tokenCount: Int?
    public let finishReason: String?
    public let reasoning: String?
    public let reasoningContent: String?
}

/// Hermes can ship native OpenAI/Anthropic-style tool calls. We capture
/// the unioned subset; argument shape varies per provider so we keep the
/// payload as a raw string the way Hermes returns it.
public struct HermesDashboardToolCall: Codable, Sendable, Equatable, Hashable {
    public let id: String?
    public let type: String?
    public let name: String?
    public let arguments: String?
}

/// Wrapper around `GET /api/sessions/{id}/messages`. Hermes returns
/// `{session_id, messages: [...]}`.
public struct HermesDashboardMessagesResponse: Codable, Sendable, Equatable {
    public let sessionId: String
    public let messages: [HermesDashboardMessage]
}

// MARK: - Skills

/// One entry in `GET /api/skills`. The dashboard returns a top-level
/// JSON array of these records.
public struct HermesDashboardSkill: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let name: String
    public let description: String?
    public let category: String?
    public let enabled: Bool

    public var id: String { name }
}

// MARK: - Config

/// `GET /api/config` returns 64 top-level keys. We model only the subset
/// the desktop UI actually consumes. Unknown fields decode away silently;
/// the typed accessors below are what Diak views read.
public struct HermesDashboardConfig: Codable, Sendable, Equatable {
    public let model: String?
    public let timezone: String?
    public let agent: HermesDashboardConfigAgent?

    /// The `agent.*` config block: agent-loop configuration.
    public struct HermesDashboardConfigAgent: Codable, Sendable, Equatable {
        public let maxIterations: Int?
        public let temperature: Double?
    }
}

// MARK: - Status

/// `GET /api/status` payload. Verified live in Phase 0.5 — see
/// `Docs/Phases/Phase1/evidence/api_api_status.json`.
public struct HermesDashboardStatus: Codable, Sendable, Equatable {
    public let version: String
    public let releaseDate: String?
    public let hermesHome: String?
    public let configPath: String?
    public let envPath: String?
    public let configVersion: Int?
    public let latestConfigVersion: Int?
    public let gatewayRunning: Bool?
    public let gatewayPid: Int?
    public let gatewayHealthUrl: String?
    public let gatewayState: String?
    public let gatewayExitReason: String?
    public let activeSessions: Int?
}

// MARK: - Cron jobs

/// Hermes' own scheduled job, served from `GET /api/cron/jobs`. This is
/// distinct from Diak's automation builder (Phase 5) — Hermes calls them
/// cron jobs, Diak wraps them in higher-level automation semantics later.
public struct HermesDashboardCronJob: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let prompt: String?
    public let skills: [String]?
    public let model: String?
    public let provider: String?
    public let schedule: HermesDashboardCronSchedule?
    public let enabled: Bool?
    public let state: String?
    public let lastRunAt: Date?
    public let nextRunAt: Date?
    public let lastStatus: String?
    public let lastError: String?
    public let deliver: String?
}

public struct HermesDashboardCronSchedule: Codable, Sendable, Equatable, Hashable {
    public let kind: String?
    public let minutes: Int?
    public let display: String?
}

// MARK: - Profiles

/// `GET /api/profiles` returns `{profiles: [...]}` per Phase 0.5 evidence.
public struct HermesDashboardProfilesResponse: Codable, Sendable, Equatable {
    public let profiles: [HermesDashboardProfile]
}

public struct HermesDashboardProfile: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let name: String
    public let path: String?
    public let isDefault: Bool?
    public let model: String?
    public let provider: String?
    public let hasEnv: Bool?
    public let skillCount: Int?

    public var id: String { name }
}

// MARK: - Model info

/// `GET /api/model/info` returns the currently-selected model + provider
/// + base URL on the active profile.
public struct HermesDashboardModelInfo: Codable, Sendable, Equatable {
    public let model: String?
    public let provider: String?
    public let baseUrl: String?
}

// MARK: - OAuth providers

/// `GET /api/providers/oauth` returns the inference-provider OAuth
/// catalog. The real response shape (per `evidence/api_api_providers_oauth.json`)
/// has just `providers`; the optional `connected` map was hypothesized
/// in the OpenAPI spec but isn't present in observed responses.
///
/// Note: this is **not** the Composio connector OAuth — that's Phase 4
/// and lives on a Diak-owned surface, not in Hermes.
public struct HermesDashboardOAuthProvidersResponse: Codable, Sendable, Equatable {
    public let providers: [HermesDashboardOAuthProvider]
}

public struct HermesDashboardOAuthProvider: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let name: String?
    public let flow: String?
    public let cliCommand: String?
    public let docsUrl: String?
    public let status: HermesDashboardOAuthProviderStatus?
}

public struct HermesDashboardOAuthProviderStatus: Codable, Sendable, Equatable, Hashable {
    public let loggedIn: Bool?
    public let source: String?
    public let sourceLabel: String?
    public let hasRefreshToken: Bool?
    // Deliberately omitted: token_preview (user-data preview),
    // expires_at (mixed-type field: sometimes Int ms, sometimes null,
    // sometimes ISO string — not needed for Phase 1 display).
    // Both fields decode-away silently from the Hermes response.
}
