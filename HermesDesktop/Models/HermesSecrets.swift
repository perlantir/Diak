import Foundation

// MARK: - Secret kind

/// Identifies which integration a secret slot belongs to. Tolerant of
/// unknown values so the daemon can roll out new integrations without
/// crashing the desktop client. M12 Slice 1 ships Composio as the first
/// concrete kind; the field metadata is what differentiates kinds.
public enum HermesSecretKind: String, Codable, Equatable, Sendable, Hashable {
    case composio
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesSecretKind(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .composio: return "Composio"
        case .unknown:  return "Unknown integration"
        }
    }
}

// MARK: - Field shape

/// Describes one editable field inside a secret slot. The kind controls
/// whether the Settings UI should render the value as a SecureField, and
/// the Keychain store treats every field consistently — the Mac app must
/// never persist sensitive raw values in `UserDefaults`.
public enum HermesSecretFieldKind: String, Codable, Equatable, Sendable, Hashable {
    /// A sensitive token or password — masked input, never echoed back.
    case apiKey = "api_key"
    /// A non-sensitive identifier (entity id, redirect URL template, base URL).
    case plainText = "plain_text"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesSecretFieldKind(rawValue: raw.lowercased()) ?? .unknown
    }

    /// True when input/storage must be treated as sensitive. The Settings
    /// UI uses this to pick `SecureField` and the descriptor never echoes
    /// the value back over the boundary.
    public var isSensitive: Bool {
        switch self {
        case .apiKey: return true
        case .plainText, .unknown: return false
        }
    }
}

/// Metadata describing one field inside a secret slot. Never carries a
/// raw value — values only travel inside `HermesSecretSaveRequest`.
public struct HermesSecretFieldDescriptor: Codable, Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: HermesSecretFieldKind
    public let label: String
    public let placeholder: String?
    public let helpText: String?
    public let isRequired: Bool

    public init(id: String,
                kind: HermesSecretFieldKind,
                label: String,
                placeholder: String? = nil,
                helpText: String? = nil,
                isRequired: Bool) {
        self.id = id
        self.kind = kind
        self.label = label
        self.placeholder = placeholder
        self.helpText = helpText
        self.isRequired = isRequired
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, label, placeholder
        case helpText = "help_text"
        case isRequired = "is_required"
    }
}

// MARK: - Descriptor

/// Top-level descriptor for one named secret slot (e.g. "composio").
/// Carries only metadata — no raw secret material crosses this type.
public struct HermesSecretDescriptor: Codable, Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: HermesSecretKind
    public let displayName: String
    public let helpText: String?
    public let fields: [HermesSecretFieldDescriptor]
    public let testActionAvailable: Bool

    public init(id: String,
                kind: HermesSecretKind,
                displayName: String,
                helpText: String? = nil,
                fields: [HermesSecretFieldDescriptor],
                testActionAvailable: Bool) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.helpText = helpText
        self.fields = fields
        self.testActionAvailable = testActionAvailable
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, fields
        case displayName = "display_name"
        case helpText = "help_text"
        case testActionAvailable = "test_action_available"
    }

    /// Field that holds the primary sensitive credential (the api key).
    /// Used by the Settings UI to drive the "Saved / Missing" badge.
    public var primarySensitiveFieldID: String? {
        fields.first { $0.kind.isSensitive }?.id
    }
}

// MARK: - Presence + validity status

/// Whether the daemon currently has any saved value for this secret slot.
/// The descriptor/status response only ever carries presence — never the
/// raw value itself.
public enum HermesSecretPresence: String, Codable, Equatable, Sendable, Hashable {
    case missing
    case saved
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesSecretPresence(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .missing: return "Missing"
        case .saved:   return "Saved"
        case .unknown: return "Unknown"
        }
    }

    public var tone: HermesStatusTone {
        switch self {
        case .missing: return .warning
        case .saved:   return .success
        case .unknown: return .neutral
        }
    }
}

/// Outcome of the most recent connectivity test, if any.
public enum HermesSecretValidity: String, Codable, Equatable, Sendable, Hashable {
    case untested
    case valid
    case invalid
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HermesSecretValidity(rawValue: raw.lowercased()) ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .untested: return "Untested"
        case .valid:    return "Valid"
        case .invalid:  return "Invalid"
        case .unknown:  return "Unknown"
        }
    }

    public var tone: HermesStatusTone {
        switch self {
        case .untested: return .neutral
        case .valid:    return .success
        case .invalid:  return .danger
        case .unknown:  return .neutral
        }
    }
}

/// Daemon-reported status for one secret slot. The Settings UI renders
/// this directly; raw values are deliberately absent.
public struct HermesSecretStatus: Codable, Equatable, Sendable, Hashable, Identifiable {
    public let id: String
    public let presence: HermesSecretPresence
    public let validity: HermesSecretValidity
    public let lastSavedAt: Date?
    public let lastTestedAt: Date?
    public let lastTestMessage: String?
    /// Subset of non-sensitive field ids the daemon has values for. Lets
    /// the Settings UI prefill plain-text fields (base URL, entity id)
    /// without ever echoing sensitive material.
    public let savedNonSensitiveFieldIDs: [String]

    public init(id: String,
                presence: HermesSecretPresence,
                validity: HermesSecretValidity,
                lastSavedAt: Date? = nil,
                lastTestedAt: Date? = nil,
                lastTestMessage: String? = nil,
                savedNonSensitiveFieldIDs: [String] = []) {
        self.id = id
        self.presence = presence
        self.validity = validity
        self.lastSavedAt = lastSavedAt
        self.lastTestedAt = lastTestedAt
        self.lastTestMessage = lastTestMessage
        self.savedNonSensitiveFieldIDs = savedNonSensitiveFieldIDs
    }

    enum CodingKeys: String, CodingKey {
        case id, presence, validity
        case lastSavedAt = "last_saved_at"
        case lastTestedAt = "last_tested_at"
        case lastTestMessage = "last_test_message"
        case savedNonSensitiveFieldIDs = "saved_non_sensitive_field_ids"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.presence = try c.decode(HermesSecretPresence.self, forKey: .presence)
        self.validity = try c.decode(HermesSecretValidity.self, forKey: .validity)
        self.lastSavedAt = HermesSecrets.decodeDateIfPresent(c, key: .lastSavedAt)
        self.lastTestedAt = HermesSecrets.decodeDateIfPresent(c, key: .lastTestedAt)
        self.lastTestMessage = try c.decodeIfPresent(String.self, forKey: .lastTestMessage)
        self.savedNonSensitiveFieldIDs = try c.decodeIfPresent([String].self, forKey: .savedNonSensitiveFieldIDs) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(presence.rawValue, forKey: .presence)
        try c.encode(validity.rawValue, forKey: .validity)
        if let lastSavedAt {
            try c.encode(ISO8601DateFormatter().string(from: lastSavedAt), forKey: .lastSavedAt)
        }
        if let lastTestedAt {
            try c.encode(ISO8601DateFormatter().string(from: lastTestedAt), forKey: .lastTestedAt)
        }
        try c.encodeIfPresent(lastTestMessage, forKey: .lastTestMessage)
        try c.encode(savedNonSensitiveFieldIDs, forKey: .savedNonSensitiveFieldIDs)
    }
}

// MARK: - Catalog response

/// Response shape for `GET /settings/secrets`. The descriptors describe
/// every secret slot the daemon supports; the statuses describe what is
/// currently saved. The boundary note is shown in Settings copy so users
/// understand the keys live in macOS Keychain, not the daemon database.
public struct HermesSecretCatalog: Codable, Equatable, Sendable {
    public var descriptors: [HermesSecretDescriptor]
    public var statuses: [HermesSecretStatus]
    public var boundaryNote: String?

    public init(descriptors: [HermesSecretDescriptor],
                statuses: [HermesSecretStatus],
                boundaryNote: String? = nil) {
        self.descriptors = descriptors
        self.statuses = statuses
        self.boundaryNote = boundaryNote
    }

    enum CodingKeys: String, CodingKey {
        case descriptors, statuses
        case boundaryNote = "boundary_note"
    }

    public func status(for id: String) -> HermesSecretStatus? {
        statuses.first { $0.id == id }
    }

    public func descriptor(for id: String) -> HermesSecretDescriptor? {
        descriptors.first { $0.id == id }
    }
}

// MARK: - Save / delete / test request payloads

/// One field value being saved. The raw `value` is sensitive when the
/// matching descriptor field is sensitive — it is sent over the local
/// HTTP boundary in plaintext (loopback only) and persisted in the
/// macOS Keychain by the desktop app, never in `UserDefaults`.
public struct HermesSecretFieldValue: Codable, Equatable, Sendable, Hashable {
    public let fieldID: String
    public let value: String

    public init(fieldID: String, value: String) {
        self.fieldID = fieldID
        self.value = value
    }

    enum CodingKeys: String, CodingKey {
        case fieldID = "field_id"
        case value
    }
}

/// Body of `POST /settings/secrets/{id}`. Carries raw values — by design
/// this is the only secrets type that does. Status/descriptor types
/// must never echo these values back.
public struct HermesSecretSaveRequest: Codable, Equatable, Sendable {
    public let id: String
    public let fields: [HermesSecretFieldValue]
    /// User has acknowledged that the value will be persisted in the
    /// macOS Keychain and pushed into the local bridge environment.
    /// Slice 1 only carries the bit; the bridge env path lands in Slice 3.
    public let acknowledgedKeychainStorage: Bool

    public init(id: String,
                fields: [HermesSecretFieldValue],
                acknowledgedKeychainStorage: Bool) {
        self.id = id
        self.fields = fields
        self.acknowledgedKeychainStorage = acknowledgedKeychainStorage
    }

    enum CodingKeys: String, CodingKey {
        case id, fields
        case acknowledgedKeychainStorage = "acknowledged_keychain_storage"
    }

    /// Convenience accessor for the Settings UI: pull a saved value out
    /// of the request without scanning the array each time.
    public func value(for fieldID: String) -> String? {
        fields.first { $0.fieldID == fieldID }?.value
    }

    public var isEmpty: Bool {
        fields.allSatisfy { $0.value.isEmpty }
    }
}

/// Returned by both save and delete — the post-mutation status plus an
/// optional human-readable note (e.g. "Restart bridge to pick up key").
public struct HermesSecretMutationResult: Codable, Equatable, Sendable {
    public let status: HermesSecretStatus
    public let requiresBridgeRestart: Bool
    public let note: String?

    public init(status: HermesSecretStatus,
                requiresBridgeRestart: Bool,
                note: String? = nil) {
        self.status = status
        self.requiresBridgeRestart = requiresBridgeRestart
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case status, note
        case requiresBridgeRestart = "requires_bridge_restart"
    }
}

/// Returned by `POST /settings/secrets/{id}/test`. Strictly an
/// observation: the daemon performs the connectivity check and reports
/// the outcome — the Mac app never tests credentials itself.
public struct HermesSecretTestResult: Codable, Equatable, Sendable {
    public let id: String
    public let isOK: Bool
    public let validity: HermesSecretValidity
    public let message: String
    public let testedAt: Date

    public init(id: String,
                isOK: Bool,
                validity: HermesSecretValidity,
                message: String,
                testedAt: Date) {
        self.id = id
        self.isOK = isOK
        self.validity = validity
        self.message = message
        self.testedAt = testedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, validity, message
        case isOK = "is_ok"
        case testedAt = "tested_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.isOK = try c.decode(Bool.self, forKey: .isOK)
        self.validity = try c.decode(HermesSecretValidity.self, forKey: .validity)
        self.message = try c.decode(String.self, forKey: .message)
        if let parsed = HermesSecrets.decodeDateIfPresent(c, key: .testedAt) {
            self.testedAt = parsed
        } else {
            throw DecodingError.dataCorruptedError(forKey: .testedAt,
                                                   in: c,
                                                   debugDescription: "Missing or unrecognized tested_at")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(isOK, forKey: .isOK)
        try c.encode(validity.rawValue, forKey: .validity)
        try c.encode(message, forKey: .message)
        try c.encode(ISO8601DateFormatter().string(from: testedAt), forKey: .testedAt)
    }
}

// MARK: - Date parsing helpers

/// Internal namespace for the secrets module. The codebase already has a
/// `HermesISO8601` helper (see `HermesSession.swift`); this thin wrapper
/// keeps date parsing localized and avoids re-implementing the lookup.
enum HermesSecrets {
    static func decodeDateIfPresent<K: CodingKey>(_ container: KeyedDecodingContainer<K>, key: K) -> Date? {
        guard let raw = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
        return HermesISO8601.parse(raw)
    }
}

// MARK: - Catalog / descriptor defaults

public extension HermesSecretDescriptor {
    /// Canonical Composio descriptor. Centralized here so the mock,
    /// Settings UI, and any local-daemon shim describe the same fields.
    static let composio = HermesSecretDescriptor(
        id: "composio",
        kind: .composio,
        displayName: "Composio",
        helpText: "API key + connector config Hermes uses to talk to Composio integrations. Stored in macOS Keychain on this Mac; never synced to iCloud.",
        fields: [
            HermesSecretFieldDescriptor(
                id: "api_key",
                kind: .apiKey,
                label: "API key",
                placeholder: "comp_live_…",
                helpText: "Found in your Composio dashboard. Required.",
                isRequired: true
            ),
            HermesSecretFieldDescriptor(
                id: "base_url",
                kind: .plainText,
                label: "Base URL",
                placeholder: "https://backend.composio.dev",
                helpText: "Override only if you self-host Composio.",
                isRequired: false
            ),
            HermesSecretFieldDescriptor(
                id: "entity_id",
                kind: .plainText,
                label: "Entity ID",
                placeholder: "default",
                helpText: "Composio account/entity scoping. Optional.",
                isRequired: false
            ),
            HermesSecretFieldDescriptor(
                id: "redirect_url",
                kind: .plainText,
                label: "Redirect URL",
                placeholder: "diak://composio/callback",
                helpText: "Where the daemon should send users after OAuth.",
                isRequired: false
            ),
            HermesSecretFieldDescriptor(
                id: "setup_url_template",
                kind: .plainText,
                label: "Setup URL template",
                placeholder: "https://composio.dev/connect/{connector}",
                helpText: "Template used when the daemon hands off connector setup.",
                isRequired: false
            )
        ],
        testActionAvailable: true
    )
}

public extension HermesSecretCatalog {
    /// Default boundary note for any catalog payload that doesn't
    /// override one. Used by mocks/tests so copy stays consistent.
    static let defaultBoundaryNote =
        "Diak stores API keys and integration config in macOS Keychain on this Mac. Hermes Engine reads them from Keychain at bridge launch — they are never written to plain config files or synced to iCloud."
}
