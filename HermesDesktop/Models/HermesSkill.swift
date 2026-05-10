import Foundation

// MARK: - Status / category / source / risk

/// Lifecycle state of a skill as reported by the daemon. The desktop app
/// surfaces these as non-mutating chips except for `enable`/`disable`,
/// which is the only state transition the M6 boundary supports.
public enum HermesSkillStatus: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case active
    case draft
    case disabled
    case archived
    case error
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesSkillStatus(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .active:   return "Active"
        case .draft:    return "Draft"
        case .disabled: return "Disabled"
        case .archived: return "Archived"
        case .error:    return "Error"
        case .unknown:  return "Unknown"
        }
    }

    public var tone: HermesStatusTone {
        switch self {
        case .active:   return .success
        case .draft:    return .info
        case .disabled: return .neutral
        case .archived: return .neutral
        case .error:    return .danger
        case .unknown:  return .neutral
        }
    }
}

/// Loose category bucket the daemon assigns. Tolerant of unknown values
/// so a daemon shipping a new category doesn't blank out the row.
public enum HermesSkillCategory: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case general
    case coding
    case writing
    case research
    case ops
    case data
    case planning
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesSkillCategory(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .general:  return "General"
        case .coding:   return "Coding"
        case .writing:  return "Writing"
        case .research: return "Research"
        case .ops:      return "Ops"
        case .data:     return "Data"
        case .planning: return "Planning"
        case .unknown:  return "Other"
        }
    }

    public var iconName: String {
        switch self {
        case .general:  return "sparkles"
        case .coding:   return "chevron.left.forwardslash.chevron.right"
        case .writing:  return "text.alignleft"
        case .research: return "magnifyingglass"
        case .ops:      return "wrench.and.screwdriver"
        case .data:     return "chart.bar"
        case .planning: return "list.bullet.rectangle"
        case .unknown:  return "circle.grid.2x2"
        }
    }
}

/// Where this skill came from. Drives the source chip and dictates which
/// management actions are safe to expose (e.g. you cannot delete a
/// daemon-builtin skill from the desktop boundary).
public enum HermesSkillSource: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case builtIn = "built_in"
    case userCreated = "user_created"
    case sharedTeam = "shared_team"
    case sessionDraft = "session_draft"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesSkillSource(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .builtIn:      return "Built-in"
        case .userCreated:  return "Created by you"
        case .sharedTeam:   return "Shared from team"
        case .sessionDraft: return "Session draft"
        case .unknown:      return "Unknown source"
        }
    }

    public var tone: HermesStatusTone {
        switch self {
        case .builtIn:      return .info
        case .userCreated:  return .success
        case .sharedTeam:   return .info
        case .sessionDraft: return .warning
        case .unknown:      return .neutral
        }
    }
}

/// Coarse summary of how risky the skill is when it runs. Mirrors
/// existing approval risk tones so the same chip style reads correctly.
public enum HermesSkillRiskStyle: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case safe
    case requiresApproval = "requires_approval"
    case sensitive
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesSkillRiskStyle(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .safe:             return "Safe"
        case .requiresApproval: return "Requires approval"
        case .sensitive:        return "Sensitive"
        case .unknown:          return "Unknown risk"
        }
    }

    public var explanation: String {
        switch self {
        case .safe:
            return "Runs without prompting. The daemon still records each invocation."
        case .requiresApproval:
            return "Each invocation queues an approval before any side effect runs."
        case .sensitive:
            return "Runs only inside trusted folders, with strict approval-gating on writes."
        case .unknown:
            return "Risk profile not reported. The desktop app treats this as approval-gated."
        }
    }

    public var tone: HermesStatusTone {
        switch self {
        case .safe:             return .success
        case .requiresApproval: return .warning
        case .sensitive:        return .danger
        case .unknown:          return .neutral
        }
    }
}

// MARK: - Related artifact

/// Pointer to a file/snippet/recording the skill bundle references. Kept
/// boundary-only — the desktop app never opens these by itself in M6.
public struct HermesSkillArtifact: Codable, Equatable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Equatable, Sendable, Hashable {
        case promptTemplate = "prompt_template"
        case file
        case toolBinding = "tool_binding"
        case note
        case unknown

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw.lowercased()) ?? .unknown
        }

        public var displayName: String {
            switch self {
            case .promptTemplate: return "Prompt template"
            case .file:           return "File reference"
            case .toolBinding:    return "Tool binding"
            case .note:           return "Note"
            case .unknown:        return "Artifact"
            }
        }

        public var iconName: String {
            switch self {
            case .promptTemplate: return "text.quote"
            case .file:           return "doc.text"
            case .toolBinding:    return "wrench.and.screwdriver"
            case .note:           return "note.text"
            case .unknown:        return "questionmark.app.dashed"
            }
        }
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let detail: String?

    public init(id: String, kind: Kind, title: String, detail: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, detail
    }
}

// MARK: - Skill record

/// One skill entry. Drives both the library list (status, category, risk
/// chip) and the detail panel (trigger summary, usage notes, artifacts).
public struct HermesSkill: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let summary: String
    public var status: HermesSkillStatus
    public let category: HermesSkillCategory
    public let source: HermesSkillSource
    public let riskStyle: HermesSkillRiskStyle
    public let version: String
    public let triggerSummary: String
    public let usageNotes: String?
    public let artifacts: [HermesSkillArtifact]
    public var isEnabled: Bool
    public let sourceSessionID: String?
    public let updatedAt: Date?
    public let installedBy: String?

    public init(id: String,
                name: String,
                summary: String,
                status: HermesSkillStatus,
                category: HermesSkillCategory,
                source: HermesSkillSource,
                riskStyle: HermesSkillRiskStyle,
                version: String,
                triggerSummary: String,
                usageNotes: String? = nil,
                artifacts: [HermesSkillArtifact] = [],
                isEnabled: Bool,
                sourceSessionID: String? = nil,
                updatedAt: Date? = nil,
                installedBy: String? = nil) {
        self.id = id
        self.name = name
        self.summary = summary
        self.status = status
        self.category = category
        self.source = source
        self.riskStyle = riskStyle
        self.version = version
        self.triggerSummary = triggerSummary
        self.usageNotes = usageNotes
        self.artifacts = artifacts
        self.isEnabled = isEnabled
        self.sourceSessionID = sourceSessionID
        self.updatedAt = updatedAt
        self.installedBy = installedBy
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case summary
        case status
        case category
        case source
        case riskStyle = "risk_style"
        case version
        case triggerSummary = "trigger_summary"
        case usageNotes = "usage_notes"
        case artifacts
        case isEnabled = "is_enabled"
        case sourceSessionID = "source_session_id"
        case updatedAt = "updated_at"
        case installedBy = "installed_by"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        self.status = try c.decodeIfPresent(HermesSkillStatus.self, forKey: .status) ?? .unknown
        self.category = try c.decodeIfPresent(HermesSkillCategory.self, forKey: .category) ?? .unknown
        self.source = try c.decodeIfPresent(HermesSkillSource.self, forKey: .source) ?? .unknown
        self.riskStyle = try c.decodeIfPresent(HermesSkillRiskStyle.self, forKey: .riskStyle) ?? .unknown
        self.version = try c.decodeIfPresent(String.self, forKey: .version) ?? "0.0.0"
        self.triggerSummary = try c.decodeIfPresent(String.self, forKey: .triggerSummary) ?? ""
        self.usageNotes = try c.decodeIfPresent(String.self, forKey: .usageNotes)
        self.artifacts = try c.decodeIfPresent([HermesSkillArtifact].self, forKey: .artifacts) ?? []
        self.isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        self.sourceSessionID = try c.decodeIfPresent(String.self, forKey: .sourceSessionID)
        if let raw = try c.decodeIfPresent(String.self, forKey: .updatedAt) {
            guard let parsed = HermesISO8601.parse(raw) else {
                throw DecodingError.dataCorruptedError(forKey: .updatedAt, in: c,
                                                       debugDescription: "Unrecognized date: \(raw)")
            }
            self.updatedAt = parsed
        } else {
            self.updatedAt = nil
        }
        self.installedBy = try c.decodeIfPresent(String.self, forKey: .installedBy)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let f = ISO8601DateFormatter()
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(summary, forKey: .summary)
        try c.encode(status.rawValue, forKey: .status)
        try c.encode(category.rawValue, forKey: .category)
        try c.encode(source.rawValue, forKey: .source)
        try c.encode(riskStyle.rawValue, forKey: .riskStyle)
        try c.encode(version, forKey: .version)
        try c.encode(triggerSummary, forKey: .triggerSummary)
        try c.encodeIfPresent(usageNotes, forKey: .usageNotes)
        try c.encode(artifacts, forKey: .artifacts)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encodeIfPresent(sourceSessionID, forKey: .sourceSessionID)
        if let updatedAt { try c.encode(f.string(from: updatedAt), forKey: .updatedAt) }
        try c.encodeIfPresent(installedBy, forKey: .installedBy)
    }
}

public extension HermesSkill {
    /// Whether enable/disable is the only mutation the desktop boundary
    /// should expose. Built-in skills are read-only from the Mac UI.
    var supportsEnableToggle: Bool {
        source != .unknown && status != .archived && status != .error
    }
}

// MARK: - Catalog & request types

/// Result returned from `skills()` — the full library plus a boundary
/// note explaining what the desktop app does and does not do.
public struct HermesSkillCatalog: Codable, Equatable, Sendable {
    public let skills: [HermesSkill]
    public let boundaryNote: String

    public init(skills: [HermesSkill], boundaryNote: String) {
        self.skills = skills
        self.boundaryNote = boundaryNote
    }

    enum CodingKeys: String, CodingKey {
        case skills
        case boundaryNote = "boundary_note"
    }
}

/// Boundary-only result of `previewSkillDraftFromSession`. Describes
/// what the daemon would extract — surfaced in the create-from-session
/// review sheet. The desktop app never installs the skill itself.
public struct HermesSkillDraftReview: Codable, Equatable, Sendable, Hashable {
    public enum ReadinessState: String, Codable, Equatable, Sendable, Hashable {
        case ready
        case needsClarification = "needs_clarification"
        case unsupportedInDesktop = "unsupported_in_desktop"
        case unknown

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = ReadinessState(rawValue: raw.lowercased()) ?? .unknown
        }

        public var displayName: String {
            switch self {
            case .ready:                return "Ready for review"
            case .needsClarification:   return "Needs clarification"
            case .unsupportedInDesktop: return "Mac app cannot draft this"
            case .unknown:              return "Unknown readiness"
            }
        }

        public var tone: HermesStatusTone {
            switch self {
            case .ready:                return .info
            case .needsClarification:   return .warning
            case .unsupportedInDesktop: return .danger
            case .unknown:              return .neutral
            }
        }
    }

    public let sessionID: String
    public let suggestedName: String
    public let suggestedSummary: String
    public let suggestedTriggerSummary: String
    public let suggestedCategory: HermesSkillCategory
    public let suggestedRiskStyle: HermesSkillRiskStyle
    public let safetyHighlights: [String]
    public let readiness: ReadinessState
    public let message: String

    public init(sessionID: String,
                suggestedName: String,
                suggestedSummary: String,
                suggestedTriggerSummary: String,
                suggestedCategory: HermesSkillCategory,
                suggestedRiskStyle: HermesSkillRiskStyle,
                safetyHighlights: [String],
                readiness: ReadinessState,
                message: String) {
        self.sessionID = sessionID
        self.suggestedName = suggestedName
        self.suggestedSummary = suggestedSummary
        self.suggestedTriggerSummary = suggestedTriggerSummary
        self.suggestedCategory = suggestedCategory
        self.suggestedRiskStyle = suggestedRiskStyle
        self.safetyHighlights = safetyHighlights
        self.readiness = readiness
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case suggestedName = "suggested_name"
        case suggestedSummary = "suggested_summary"
        case suggestedTriggerSummary = "suggested_trigger_summary"
        case suggestedCategory = "suggested_category"
        case suggestedRiskStyle = "suggested_risk_style"
        case safetyHighlights = "safety_highlights"
        case readiness
        case message
    }
}

/// Request body for `submitSkillDraft`. The desktop boundary lets the
/// user edit the suggested fields before the daemon actually installs.
public struct HermesSkillDraftRequest: Codable, Equatable, Sendable {
    public let sessionID: String
    public let name: String
    public let summary: String
    public let triggerSummary: String
    public let category: HermesSkillCategory
    public let riskStyle: HermesSkillRiskStyle
    public let acknowledgedDaemonInstall: Bool

    public init(sessionID: String,
                name: String,
                summary: String,
                triggerSummary: String,
                category: HermesSkillCategory,
                riskStyle: HermesSkillRiskStyle,
                acknowledgedDaemonInstall: Bool) {
        self.sessionID = sessionID
        self.name = name
        self.summary = summary
        self.triggerSummary = triggerSummary
        self.category = category
        self.riskStyle = riskStyle
        self.acknowledgedDaemonInstall = acknowledgedDaemonInstall
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case name
        case summary
        case triggerSummary = "trigger_summary"
        case category
        case riskStyle = "risk_style"
        case acknowledgedDaemonInstall = "acknowledged_daemon_install"
    }
}

/// Generic result of a skill mutation that returns the updated record.
public struct HermesSkillMutationResult: Codable, Equatable, Sendable {
    public let skill: HermesSkill
    public let note: String?

    public init(skill: HermesSkill, note: String? = nil) {
        self.skill = skill
        self.note = note
    }
}

/// Request body for `createSkillDraft` — the direct add path that does
/// not require an existing chat session. The Mac app captures the
/// fields the user authors, the daemon owns install/execution.
public struct HermesSkillDirectDraftRequest: Codable, Equatable, Sendable {
    public let name: String
    public let summary: String
    public let triggerSummary: String
    public let category: HermesSkillCategory
    public let riskStyle: HermesSkillRiskStyle
    public let instructions: String?
    public let acknowledgedDaemonInstall: Bool

    public init(name: String,
                summary: String,
                triggerSummary: String,
                category: HermesSkillCategory,
                riskStyle: HermesSkillRiskStyle,
                instructions: String?,
                acknowledgedDaemonInstall: Bool) {
        self.name = name
        self.summary = summary
        self.triggerSummary = triggerSummary
        self.category = category
        self.riskStyle = riskStyle
        self.instructions = instructions
        self.acknowledgedDaemonInstall = acknowledgedDaemonInstall
    }

    enum CodingKeys: String, CodingKey {
        case name
        case summary
        case triggerSummary = "trigger_summary"
        case category
        case riskStyle = "risk_style"
        case instructions
        case acknowledgedDaemonInstall = "acknowledged_daemon_install"
    }
}
