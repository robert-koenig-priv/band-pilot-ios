import Foundation
import Security

/// Minimal Keychain wrapper for the JWT + the logged-in user (the Android app used
/// SharedPreferences; the token belongs in the Keychain on iOS).
public struct KeychainStore: Sendable {
    private let service: String
    private let tokenKey = "auth-token"
    private let userKey = "auth-user"

    public init(service: String = "com.bandpilot.session") {
        self.service = service
    }

    public func saveToken(_ token: String) { save(tokenKey, Data(token.utf8)) }
    public func readToken() -> String? { read(tokenKey).flatMap { String(data: $0, encoding: .utf8) } }

    public func saveUser(_ user: User) {
        if let data = try? JSONEncoder().encode(user) { save(userKey, data) }
    }
    public func readUser() -> User? {
        read(userKey).flatMap { try? JSONDecoder().decode(User.self, from: $0) }
    }

    public func clear() { delete(tokenKey); delete(userKey) }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func save(_ account: String, _ data: Data) {
        SecItemDelete(baseQuery(account) as CFDictionary)
        var add = baseQuery(account)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private func read(_ account: String) -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func delete(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }
}
