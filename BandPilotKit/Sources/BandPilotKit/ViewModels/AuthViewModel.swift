import Foundation
import Observation

/// Combined sign-in / register form state (mirrors the Android AuthViewModel). Registration only
/// sends the request — the user must open the emailed verification link before signing in.
@MainActor
@Observable
public final class AuthViewModel {
    public enum Mode: Sendable { case login, register }

    public var mode: Mode = .login
    public var busy = false
    public var error: String?
    public var info: String?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let session: SessionStore

    public init(api: APIClient, session: SessionStore) {
        self.api = api
        self.session = session
    }

    public func toggleMode() {
        mode = (mode == .login) ? .register : .login
        error = nil
        info = nil
    }

    public func login(email: String, password: String) async {
        busy = true; error = nil; info = nil
        do {
            let resp = try await api.send(.login(.init(email: email, password: password)))
            session.signIn(token: resp.accessToken, user: resp.user)
        } catch let apiError as APIError {
            error = apiError.userMessage
        } catch let other {
            error = other.localizedDescription
        }
        busy = false
    }

    public func register(firstName: String, lastName: String, email: String, password: String) async {
        busy = true; error = nil; info = nil
        do {
            _ = try await api.send(.register(.init(email: email, password: password, firstName: firstName, lastName: lastName)))
            mode = .login
            info = "Account created. Open the verification link we emailed you, then sign in."
        } catch let apiError as APIError {
            error = apiError.userMessage
        } catch let other {
            error = other.localizedDescription
        }
        busy = false
    }

    /// Requests a reset email. The emailed link opens the web reset page (iOS doesn't
    /// set the new password in-app), so success just shows the generic "check your email"
    /// hint. Message is generic on purpose — never reveals whether the account exists.
    public func forgotPassword(email: String) async {
        busy = true; error = nil; info = nil
        do {
            _ = try await api.send(.forgotPassword(.init(email: email)))
            info = "If an account exists for that email, we've sent a password reset link."
        } catch let apiError as APIError {
            error = apiError.userMessage
        } catch let other {
            error = other.localizedDescription
        }
        busy = false
    }
}
