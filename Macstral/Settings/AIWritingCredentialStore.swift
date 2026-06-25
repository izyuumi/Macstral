import Foundation
import Security

// MARK: - AIWritingCredentialStoring

protocol AIWritingCredentialStoring: AnyObject {
    func loadAPIKey() -> String?
    func saveAPIKey(_ key: String) throws
    func clearAPIKey() throws
}

// MARK: - KeychainAIWritingCredentialStore

/// Stores the user's bring-your-own-key credential for online writing providers.
final class KeychainAIWritingCredentialStore: AIWritingCredentialStoring {

    static let shared = KeychainAIWritingCredentialStore()

    private let service: String
    private let account: String

    init(service: String = "to.yumi.Macstral.ai-writing", account: String = "api-key") {
        self.service = service
        self.account = account
    }

    func loadAPIKey() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try clearAPIKey()
            return
        }

        let data = Data(trimmed.utf8)
        let query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AIWritingCredentialStoreError.keychain(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw AIWritingCredentialStoreError.keychain(updateStatus)
        }
    }

    func clearAPIKey() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AIWritingCredentialStoreError.keychain(status)
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

// MARK: - InMemoryAIWritingCredentialStore

final class InMemoryAIWritingCredentialStore: AIWritingCredentialStoring {
    private var key: String?

    init(seed: String? = nil) {
        self.key = seed
    }

    func loadAPIKey() -> String? { key }
    func saveAPIKey(_ key: String) throws { self.key = key.trimmingCharacters(in: .whitespacesAndNewlines) }
    func clearAPIKey() throws { key = nil }
}

// MARK: - AIWritingCredentialStoreError

enum AIWritingCredentialStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
            return "Keychain error (\(status)): \(message)"
        }
    }
}
