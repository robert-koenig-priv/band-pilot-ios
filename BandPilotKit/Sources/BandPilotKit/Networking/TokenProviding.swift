import Foundation

/// Supplies the bearer token to the `APIClient` and reacts to a 401. `SessionStore` conforms;
/// keeping it a protocol breaks the client↔session reference cycle. Main-actor isolated because
/// the session is UI-observable state.
public protocol TokenProviding: AnyObject, Sendable {
    @MainActor var token: String? { get }
    @MainActor func handleUnauthorized()
}
