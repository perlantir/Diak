import Foundation

// MARK: - Scope / source / confidence

/// Scope a memory item is keyed against. The desktop app reads these as
/// chips; mutations may change scope but must always go through the
/// edit-review flow rather than auto-mutating.
public enum HermesMemoryScope: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case user
    case project
    case session
    case global
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesMemoryScope(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .user:    return "About you"
        case .project: return "Project"
        case .session: return "Session"
        case .global:  return "Global"
        case .unknown: return "Unknown scope"
        }
    }

    public var iconName: String {
        switch self {
        case .user:    return "person.crop.circle"
        case .project: return "folder"
        case .session: return "bubble.left.and.bubble.right"
        case .global:  return "globe"
        case .unknown: return "questionmark.app.dashed"
        }
    }

    public var tone: HermesStatusTone {
        switch self {
        case .user:    return .info
        case .project: return .success
        case .session: return .neutral
        case .global:  return .warning
        case .unknown: return .neutral
        }
    }
}

/// How this memory entry came to exist. Drives the source chip and
/// disambiguates "Hermes wrote this" from "you wrote this".
public enum HermesMemorySource: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case manual
    case autoExtracted = "auto_extracted"
    case sessionLearned = "session_learned"
    case importedReference = "imported_reference"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesMemorySource(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .manual:            return "You added"
        case .autoExtracted:     return "Auto-extracted"
        case .sessionLearned:    return "Learned from session"
        case .importedReference: return "Imported"
        case .unknown:           return "Unknown source"
        }
    }

    public var tone: HermesStatusTone {
        switch self {
        case .manual:            return .success
        case .autoExtracted:     return .info
        case .sessionLearned:    return .info
        case .importedReference: return .neutral
        case .unknown:           return .neutral
        }
    }
}

/// Confidence the daemon attaches to the memory. The desktop app shows
/// this so users can decide what to trust without re-prompting.
public enum HermesMemoryConfidence: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case high
    case medium
    case low
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesMemoryConfidence(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .high:    return "High confidence"
        case .medium:  return "Medium confidence"
        case .low:     return "Low confidence"
        case .unknown: return "Confidence unknown"
        }
    }

    public var tone: HermesStatusTone {
        switch self {
        case .high:    return .success
        case .medium:  return .info
        case .low:     return .warning
        case .unknown: return .neutral
        }
    }
}

// MARK: - Memory record

/// One memory item. Drives the dashboard list and the edit/delete sheet.
/// Mutations are review-oriented — the desktop boundary cannot silently
/// rewrite the underlying daemon store.
public struct HermesMemoryItem: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: String
    public var title: String
    public var body: String
    public var scope: HermesMemoryScope
    public let source: HermesMemorySource
    public let confidence: HermesMemoryConfidence
    public let tags: [String]
    public let projectRef: HermesProjectRef?
    public let sessionID: String?
    public let createdAt: Date?
    public let updatedAt: Date?
    public var isPinned: Bool

    public init(id: String,
                title: String,
                body: String,
                scope: HermesMemoryScope,
                source: HermesMemorySource,
                confidence: HermesMemoryConfidence,
                tags: [String] = [],
                projectRef: HermesProjectRef? = nil,
                sessionID: String? = nil,
                createdAt: Date? = nil,
                updatedAt: Date? = nil,
                isPinned: Bool = false) {
        self.id = id
        self.title = title
        self.body = body
        self.scope = scope
        self.source = source
        self.confidence = confidence
        self.tags = tags
        self.projectRef = projectRef
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case scope
        case source
        case confidence
        case tags
        case projectRef = "project_ref"
        case sessionID = "session_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isPinned = "is_pinned"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        self.scope = try c.decodeIfPresent(HermesMemoryScope.self, forKey: .scope) ?? .unknown
        self.source = try c.decodeIfPresent(HermesMemorySource.self, forKey: .source) ?? .unknown
        self.confidence = try c.decodeIfPresent(HermesMemoryConfidence.self, forKey: .confidence) ?? .unknown
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.projectRef = try c.decodeIfPresent(HermesProjectRef.self, forKey: .projectRef)
        self.sessionID = try c.decodeIfPresent(String.self, forKey: .sessionID)
        if let raw = try c.decodeIfPresent(String.self, forKey: .createdAt) {
            self.createdAt = HermesISO8601.parse(raw)
        } else {
            self.createdAt = nil
        }
        if let raw = try c.decodeIfPresent(String.self, forKey: .updatedAt) {
            self.updatedAt = HermesISO8601.parse(raw)
        } else {
            self.updatedAt = nil
        }
        self.isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let f = ISO8601DateFormatter()
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(body, forKey: .body)
        try c.encode(scope.rawValue, forKey: .scope)
        try c.encode(source.rawValue, forKey: .source)
        try c.encode(confidence.rawValue, forKey: .confidence)
        try c.encode(tags, forKey: .tags)
        try c.encodeIfPresent(projectRef, forKey: .projectRef)
        try c.encodeIfPresent(sessionID, forKey: .sessionID)
        if let createdAt { try c.encode(f.string(from: createdAt), forKey: .createdAt) }
        if let updatedAt { try c.encode(f.string(from: updatedAt), forKey: .updatedAt) }
        try c.encode(isPinned, forKey: .isPinned)
    }
}

public extension HermesMemoryItem {
    /// Short scope/source line surfaced in the list row.
    var scopeLine: String {
        if let project = projectRef, scope == .project {
            return "\(scope.displayName) · \(project.name)"
        }
        return scope.displayName
    }

    /// Whether the desktop app should let the user delete this item.
    /// Auto-extracted entries can be deleted (the user owns the surface);
    /// imported references are read-only at the desktop boundary.
    var supportsDelete: Bool {
        source != .importedReference
    }
}

// MARK: - Dashboard / requests

/// Result of `memoryItems()` — the full dashboard payload plus a
/// boundary note explaining what the desktop app does and does not do.
public struct HermesMemoryDashboard: Codable, Equatable, Sendable {
    public let items: [HermesMemoryItem]
    public let boundaryNote: String
    public let pinnedCount: Int
    public let totalCount: Int

    public init(items: [HermesMemoryItem],
                boundaryNote: String,
                pinnedCount: Int,
                totalCount: Int) {
        self.items = items
        self.boundaryNote = boundaryNote
        self.pinnedCount = pinnedCount
        self.totalCount = totalCount
    }

    enum CodingKeys: String, CodingKey {
        case items
        case boundaryNote = "boundary_note"
        case pinnedCount = "pinned_count"
        case totalCount = "total_count"
    }
}

/// Request body for `createMemoryItem`. Creation is intentionally explicit
/// and review-gated so the desktop app cannot silently write durable memory.
public struct HermesMemoryCreateRequest: Codable, Equatable, Sendable {
    public let title: String
    public let body: String
    public let scope: HermesMemoryScope
    public let isPinned: Bool
    public let acknowledgedReview: Bool

    public init(title: String,
                body: String,
                scope: HermesMemoryScope = .user,
                isPinned: Bool = false,
                acknowledgedReview: Bool) {
        self.title = title
        self.body = body
        self.scope = scope
        self.isPinned = isPinned
        self.acknowledgedReview = acknowledgedReview
    }

    enum CodingKeys: String, CodingKey {
        case title, body, scope
        case isPinned = "is_pinned"
        case acknowledgedReview = "acknowledged_review"
    }
}

/// Request body for `updateMemoryItem`. Every field is optional except
/// id; an entirely-empty update is rejected at the boundary so we don't
/// burn a daemon round-trip on a no-op.
public struct HermesMemoryUpdate: Codable, Equatable, Sendable {
    public let id: String
    public let title: String?
    public let body: String?
    public let scope: HermesMemoryScope?
    public let isPinned: Bool?
    public let acknowledgedReview: Bool

    public init(id: String,
                title: String? = nil,
                body: String? = nil,
                scope: HermesMemoryScope? = nil,
                isPinned: Bool? = nil,
                acknowledgedReview: Bool) {
        self.id = id
        self.title = title
        self.body = body
        self.scope = scope
        self.isPinned = isPinned
        self.acknowledgedReview = acknowledgedReview
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case scope
        case isPinned = "is_pinned"
        case acknowledgedReview = "acknowledged_review"
    }

    public var isEmpty: Bool {
        title == nil && body == nil && scope == nil && isPinned == nil
    }
}

/// Result of any memory mutation that returns the updated record.
public struct HermesMemoryMutationResult: Codable, Equatable, Sendable {
    public let item: HermesMemoryItem
    public let note: String?

    public init(item: HermesMemoryItem, note: String? = nil) {
        self.item = item
        self.note = note
    }
}

/// Result of `deleteMemoryItem`. Mirrors the automation/connector delete
/// shape so the UI can report success consistently.
public struct HermesMemoryDeleteResult: Codable, Equatable, Sendable {
    public let deleted: Bool
    public let id: String
    public let note: String?

    public init(deleted: Bool, id: String, note: String? = nil) {
        self.deleted = deleted
        self.id = id
        self.note = note
    }
}
