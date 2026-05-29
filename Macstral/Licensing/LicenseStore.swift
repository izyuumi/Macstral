import Foundation
import Security

// MARK: - LicenseRecord

/// The persisted credentials proving a Pro purchase on this Mac.
struct LicenseRecord: Codable, Equatable {
    /// The Lemon Squeezy license key the user entered.
    var key: String
    /// The activation instance ID returned by `/activate`, used for `/validate` and `/deactivate`.
    var instanceID: String
    /// Human-readable instance name registered with Lemon Squeezy (usually the machine name).
    var instanceName: String
    /// Timestamp of the last successful online validation — drives the offline grace window.
    var lastValidated: Date
}

// MARK: - LicenseStore

/// Abstraction over the persistent credential store so the manager can be unit-tested
/// with an in-memory implementation instead of the real Keychain.
protocol LicenseStore: AnyObject {
    func load() -> LicenseRecord?
    func save(_ record: LicenseRecord) throws
    func clear() throws
}

// MARK: - KeychainLicenseStore

/// Production `LicenseStore` backed by the macOS Keychain. The record is stored as a single
/// JSON blob under a generic-password item. Keychain (not UserDefaults) is used so the
/// credentials survive reinstalls and are not trivially editable by the user.
final class KeychainLicenseStore: LicenseStore {

    private let service: String
    private let account: String

    init(service: String = "to.yumi.Macstral.license", account: String = "pro") {
        self.service = service
        self.account = account
    }

    func load() -> LicenseRecord? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(LicenseRecord.self, from: data)
    }

    func save(_ record: LicenseRecord) throws {
        let data = try JSONEncoder().encode(record)
        let query = baseQuery()

        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw LicenseStoreError.keychain(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw LicenseStoreError.keychain(updateStatus)
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LicenseStoreError.keychain(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

// MARK: - InMemoryLicenseStore

/// Non-persistent `LicenseStore` for unit tests and previews.
final class InMemoryLicenseStore: LicenseStore {
    private var record: LicenseRecord?

    init(seed: LicenseRecord? = nil) {
        self.record = seed
    }

    func load() -> LicenseRecord? { record }
    func save(_ record: LicenseRecord) throws { self.record = record }
    func clear() throws { record = nil }
}

// MARK: - LicenseStoreError

enum LicenseStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
            return "Keychain error (\(status)): \(message)"
        }
    }
}
