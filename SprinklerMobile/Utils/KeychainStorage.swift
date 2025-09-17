import Foundation
import Security

protocol KeychainStoring {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String) throws
    func deleteValue(forKey key: String)
}

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
}

struct KeychainStorage: KeychainStoring {
    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.sprinkler.app") {
        self.service = service
    }

    func string(forKey key: String) -> String? {
        var query = baseQuery(forKey: key)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = kCFBooleanTrue

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else { return }

        var query = baseQuery(forKey: key)
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(baseQuery(forKey: key) as CFDictionary,
                                             [kSecValueData as String: data] as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func deleteValue(forKey key: String) {
        let query = baseQuery(forKey: key)
        SecItemDelete(query as CFDictionary)
    }

    private func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
    }
}
