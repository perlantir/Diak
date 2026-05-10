import Foundation
import Security

/// Typed errors surfaced by the Keychain-backed secret store. The
/// Settings UI maps these to user-actionable copy in Slice 2; for now
/// they exist so view models written later can render specific guidance
/// rather than a generic "Keychain failed" message.
public enum KeychainSecretStoreError: Error, Equatable, Sendable {
    case emptyAccount
    case emptyValue
    case encodingFailed
    case unhandled(status: OSStatus)

    public var userFacingMessage: String {
        switch self {
        case .emptyAccount:
            return "Diak tried to save an unnamed secret. Pick a key id before saving."
        case .emptyValue:
            return "Diak tried to save an empty value. Use 'Remove' instead to clear a key."
        case .encodingFailed:
            return "Diak could not encode that secret value for the macOS Keychain."
        case .unhandled(let status):
            return "macOS Keychain rejected the change (OSStatus \(status))."
        }
    }
}

/// Protocol used by view models so the in-memory test double and the
/// real Keychain store are interchangeable. Slice 1 only exercises this
/// behind the API client + tests; Slice 2 will inject it into the
/// Settings view models.
public protocol SecretStore: Sendable {
    func setSecret(_ value: String, account: String) throws
    func getSecret(account: String) throws -> String?
    func deleteSecret(account: String) throws
    func exists(account: String) throws -> Bool
    func listAccounts() throws -> [String]
}

/// macOS Keychain-backed store for Diak's per-key secret material.
/// Each (`service`, `account`) pair maps to one generic password item.
///
/// `service` is namespaced (default `com.uberkiwi.diak.secrets`) so test
/// suites can inject a unique ephemeral service id and avoid clobbering
/// the developer's real Keychain entries during XCTest runs.
///
/// `account` is the per-field key used by the Settings layer, of the
/// shape `<descriptorID>.<fieldID>` (e.g. `composio.api_key`). The store
/// itself does not enforce that schema — it just persists the bytes.
public final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    public static let defaultService = "com.uberkiwi.diak.secrets"

    public let service: String
    private let accessGroup: String?

    public init(service: String = KeychainSecretStore.defaultService,
                accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    // MARK: - Mutations

    public func setSecret(_ value: String, account: String) throws {
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccount.isEmpty else { throw KeychainSecretStoreError.emptyAccount }
        guard !value.isEmpty else { throw KeychainSecretStoreError.emptyValue }
        guard let data = value.data(using: .utf8) else {
            throw KeychainSecretStoreError.encodingFailed
        }

        var query = baseQuery(account: trimmedAccount)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // Update the existing item in place.
            let updateQuery = baseQuery(account: trimmedAccount)
            let updates: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updates as CFDictionary)
            if updateStatus != errSecSuccess {
                throw KeychainSecretStoreError.unhandled(status: updateStatus)
            }
        default:
            throw KeychainSecretStoreError.unhandled(status: addStatus)
        }
    }

    public func deleteSecret(account: String) throws {
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccount.isEmpty else { throw KeychainSecretStoreError.emptyAccount }
        let query = baseQuery(account: trimmedAccount)
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainSecretStoreError.unhandled(status: status)
        }
    }

    // MARK: - Reads

    public func getSecret(account: String) throws -> String? {
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccount.isEmpty else { throw KeychainSecretStoreError.emptyAccount }
        var query = baseQuery(account: trimmedAccount)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                return nil
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainSecretStoreError.unhandled(status: status)
        }
    }

    public func exists(account: String) throws -> Bool {
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccount.isEmpty else { throw KeychainSecretStoreError.emptyAccount }
        var query = baseQuery(account: trimmedAccount)
        query[kSecReturnData as String] = kCFBooleanFalse
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            return false
        default:
            throw KeychainSecretStoreError.unhandled(status: status)
        }
    }

    public func listAccounts() throws -> [String] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: kCFBooleanTrue as Any
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            let entries = item as? [[String: Any]] ?? []
            return entries.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
        case errSecItemNotFound:
            return []
        default:
            throw KeychainSecretStoreError.unhandled(status: status)
        }
    }

    // MARK: - Internals

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

// MARK: - In-memory double

/// Process-local in-memory `SecretStore`. Used by previews and tests
/// where touching the macOS Keychain would either fail (CI sandbox) or
/// leave state behind across runs. Production code paths must use
/// `KeychainSecretStore`.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    public init(initial: [String: String] = [:]) {
        self.storage = initial
    }

    public func setSecret(_ value: String, account: String) throws {
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccount.isEmpty else { throw KeychainSecretStoreError.emptyAccount }
        guard !value.isEmpty else { throw KeychainSecretStoreError.emptyValue }
        lock.lock(); defer { lock.unlock() }
        storage[trimmedAccount] = value
    }

    public func getSecret(account: String) throws -> String? {
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccount.isEmpty else { throw KeychainSecretStoreError.emptyAccount }
        lock.lock(); defer { lock.unlock() }
        return storage[trimmedAccount]
    }

    public func deleteSecret(account: String) throws {
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccount.isEmpty else { throw KeychainSecretStoreError.emptyAccount }
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: trimmedAccount)
    }

    public func exists(account: String) throws -> Bool {
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAccount.isEmpty else { throw KeychainSecretStoreError.emptyAccount }
        lock.lock(); defer { lock.unlock() }
        return storage[trimmedAccount] != nil
    }

    public func listAccounts() throws -> [String] {
        lock.lock(); defer { lock.unlock() }
        return storage.keys.sorted()
    }
}
