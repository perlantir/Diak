import Foundation

/// Persisted canvas artifact/document reference for a session. The
/// desktop app reads these through the API boundary; the daemon owns
/// real execution (browser, code, design generation) and storage.
///
/// `kind` maps onto a `HermesCanvasTab` so the canvas UI can pin each
/// artifact under the right surface without duplicating the tab
/// taxonomy. Decoding is tolerant of unknown kinds so the UI does not
/// crash on new daemon vocabulary.
public struct HermesCanvasArtifact: Codable, Equatable, Sendable, Identifiable, Hashable {
    public enum Kind: String, Codable, Equatable, Sendable, CaseIterable {
        case document
        case code
        case browser
        case design
        case board
        case other
        case unknown

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw.lowercased()) ?? .unknown
        }

        public var canvasTab: HermesCanvasTab {
            switch self {
            case .document, .other, .unknown: return .document
            case .code:    return .code
            case .browser: return .browser
            case .design:  return .design
            case .board:   return .board
            }
        }
    }

    public let id: String
    public let sessionID: String
    public let kind: Kind
    public let title: String
    public let summary: String?
    /// Short inline preview (excerpt / URL / caption) the canvas can
    /// render without re-fetching. The daemon stays responsible for the
    /// full payload.
    public let preview: String?
    public let createdAt: Date
    public let updatedAt: Date?
    /// Optional underlying file/link/command reference. Reused from the
    /// existing action-evidence vocabulary so artifact chips can share
    /// the same renderer when present.
    public let ref: HermesArtifactRef?

    public init(id: String,
                sessionID: String,
                kind: Kind,
                title: String,
                summary: String? = nil,
                preview: String? = nil,
                createdAt: Date,
                updatedAt: Date? = nil,
                ref: HermesArtifactRef? = nil) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.title = title
        self.summary = summary
        self.preview = preview
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.ref = ref
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case kind
        case title
        case summary
        case preview
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case ref
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.sessionID = try c.decode(String.self, forKey: .sessionID)
        self.kind = try c.decode(Kind.self, forKey: .kind)
        self.title = try c.decode(String.self, forKey: .title)
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary)
        self.preview = try c.decodeIfPresent(String.self, forKey: .preview)
        let createdRaw = try c.decode(String.self, forKey: .createdAt)
        guard let created = HermesISO8601.parse(createdRaw) else {
            throw DecodingError.dataCorruptedError(forKey: .createdAt,
                                                   in: c,
                                                   debugDescription: "Unrecognized date: \(createdRaw)")
        }
        self.createdAt = created
        if let updatedRaw = try c.decodeIfPresent(String.self, forKey: .updatedAt) {
            self.updatedAt = HermesISO8601.parse(updatedRaw)
        } else {
            self.updatedAt = nil
        }
        self.ref = try c.decodeIfPresent(HermesArtifactRef.self, forKey: .ref)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(kind.rawValue, forKey: .kind)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encodeIfPresent(preview, forKey: .preview)
        try c.encode(ISO8601DateFormatter().string(from: createdAt), forKey: .createdAt)
        if let updatedAt {
            try c.encode(ISO8601DateFormatter().string(from: updatedAt), forKey: .updatedAt)
        }
        try c.encodeIfPresent(ref, forKey: .ref)
    }
}

/// Wire payload returned by `GET /sessions/{id}/canvas/artifacts`. The
/// `boundaryNote` mirrors the connector/skill/memory pattern so the UI
/// can surface a daemon-handoff explainer without inventing copy.
public struct HermesCanvasArtifactList: Codable, Equatable, Sendable {
    public let sessionID: String
    public let artifacts: [HermesCanvasArtifact]
    public let boundaryNote: String?

    public init(sessionID: String,
                artifacts: [HermesCanvasArtifact],
                boundaryNote: String? = nil) {
        self.sessionID = sessionID
        self.artifacts = artifacts
        self.boundaryNote = boundaryNote
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case artifacts
        case boundaryNote = "boundary_note"
    }
}
