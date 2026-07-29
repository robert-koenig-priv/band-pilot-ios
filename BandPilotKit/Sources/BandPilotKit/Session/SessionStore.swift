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

    /// True between an actual sign-in and the first ``consumeJustSignedIn()`` call.
    ///
    /// Deliberately **not** persisted: restoring a session from the Keychain in `init` is not a sign-in,
    /// so the beta notice in `RootView` appears after signing in rather than on every cold start. Also
    /// deliberately not observed — it is read imperatively and must not itself redraw a view. Mirrors
    /// `Session.justLoggedIn` in the Android app, which drives the same notice there.
    @ObservationIgnored private var justSignedIn = false

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
        justSignedIn = true
        keychain.saveToken(token)
        keychain.saveUser(user)
    }

    /// Reads and clears ``justSignedIn``, so a caller acts on one sign-in exactly once.
    public func consumeJustSignedIn() -> Bool {
        defer { justSignedIn = false }
        return justSignedIn
    }

    public func handleUnauthorized() { signOut() }

    public func signOut() {
        token = nil
        user = nil
        keychain.clear()
    }
}
