import Foundation
import Security

/// macOS Keychain wrapper for the Hermes API Server bearer key.
///
/// Diak stores the API Server key in the system Keychain rather than in
/// `~/.hermes/.env` (per PROJECT_STATE.md Decision #6: "the API Server
/// key lives in Diak's Keychain entry"). Hermes itself still reads its
/// own copy from `~/.hermes/.env` on startup; Diak's Keychain copy is
/// the one the desktop client uses for auth. Keeping the two in sync is
/// a UI concern — when the user changes the API Server key from Diak's
/// Settings panel, Diak (a) writes the new value via this store and
/// (b) writes the new value into `~/.hermes/.env` and asks the supervisor
/// to restart the gateway. Item (b) is a Phase 4-ish concern; for Phase
/// 1 we model only this store.
///
/// The store uses generic-password Keychain items keyed by `service +
/// account`. Service defaults to `com.uberkiwi.diak.hermes-api-server`;
/// account is configurable so tests can isolate themselves with unique
/// account names.
public final class APIServerKeychainStore: Sendable {

    public enum KeychainError: Error, Equatable {
        /// Underlying `SecItem*` call returned an `OSStatus` other than
        /// `errSecSuccess` / `errSecItemNotFound`.
        case osStatus(Int32)
        /// Stored value existed but couldn't be decoded as UTF-8.
        case malformedValue
    }

    public let service: String
    public let account: String

    public init(
        service: String = "com.uberkiwi.diak.hermes-api-server",
        account: String = "api-server-key"
    ) {
        self.service = service
        self.account = account
    }

    /// Persist `key` to the Keychain, replacing any prior value for this
    /// `(service, account)` pair.
    public func store(key: String) throws {
        let data = Data(key.utf8)

        // First, try to update the existing item. If it doesn't exist,
        // fall through to add. We do it in this order so the kSecAttr
        // values used on add match what update expects on the same item.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            // Synchronizable=false so the key never sync to iCloud
            // Keychain. The API Server is per-Mac infrastructure.
            addQuery[kSecAttrSynchronizable as String] = kCFBooleanFalse
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw KeychainError.osStatus(addStatus)
            }
            return
        }
        throw KeychainError.osStatus(updateStatus)
    }

    /// Returns the stored key, or `nil` if no entry exists for this
    /// `(service, account)` pair.
    public func loadKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        if status != errSecSuccess {
            throw KeychainError.osStatus(status)
        }
        guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.malformedValue
        }
        return string
    }

    /// Remove the stored entry. Idempotent — succeeds whether the entry
    /// existed or not.
    public func deleteKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.osStatus(status)
        }
    }
}
