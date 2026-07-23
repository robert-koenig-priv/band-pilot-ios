import Foundation
import Observation

/// The logged-in session. Drives the app's auth gate and supplies the bearer token to the client.
/// Restores from the Keychain on launch; a 401 anywhere clears it (via `handleUnauthorized`).
@MainActor
@Observable
public final class SessionStore: TokenProviding {
    public private(set) var user: User?
    public private(set) var token: String?

    public var isAuthenticated: Bool { token != nil && user != nil }

    @ObservationIgnored private let keychain: KeychainStore

    public init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
        self.token = keychain.readToken()
        self.user = keychain.readUser()
        // Never leave a half-restored session around.
        if token == nil || user == nil { signOut() }
    }

    public func signIn(token: String, user: User) {
        self.token = token
        self.user = user
        keychain.saveToken(token)
        keychain.saveUser(user)
    }

    public func handleUnauthorized() { signOut() }

    public func signOut() {
        token = nil
        user = nil
        keychain.clear()
    }
}
