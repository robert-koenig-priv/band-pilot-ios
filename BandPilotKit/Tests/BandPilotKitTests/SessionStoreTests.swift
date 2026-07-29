import XCTest
@testable import BandPilotKit

/// The sign-in flag behind the beta notice.
///
/// Worth its own test because the distinction it encodes is invisible in the type: `justSignedIn` must be
/// true after an actual sign-in and false after a session is *restored*, or the notice greets a returning
/// user on every cold start — which is how a notice stops being read.
///
/// Each test gets its own Keychain service name so the real store can be used without one test's session
/// leaking into another's.
@MainActor
final class SessionStoreTests: XCTestCase {

    private func makeStore() -> SessionStore {
        SessionStore(keychain: KeychainStore(service: "com.bandpilot.test.\(UUID().uuidString)"))
    }

    private let user = User(
        id: 1,
        email: "beta@example.com",
        firstName: "Beta",
        lastName: "Tester",
        emailVerified: true
    )

    func testSigningInRaisesTheFlagExactlyOnce() {
        let session = makeStore()
        XCTAssertFalse(session.consumeJustSignedIn(), "a fresh store has not signed anyone in")

        session.signIn(token: "t", user: user)

        XCTAssertTrue(session.consumeJustSignedIn(), "the sign-in should be reported once")
        XCTAssertFalse(session.consumeJustSignedIn(), "and only once — this is what stops it re-showing")
    }

    func testRestoringASessionIsNotASignIn() {
        // The whole point of the flag. The first store persists a session; the second one restores it in
        // `init`, exactly as a cold launch does, and must not claim anyone just signed in.
        let service = "com.bandpilot.test.\(UUID().uuidString)"
        let first = SessionStore(keychain: KeychainStore(service: service))
        first.signIn(token: "t", user: user)
        _ = first.consumeJustSignedIn()

        let restored = SessionStore(keychain: KeychainStore(service: service))

        XCTAssertTrue(restored.isAuthenticated, "the session should have been restored")
        XCTAssertFalse(restored.consumeJustSignedIn(), "a restored session is not a sign-in")
        restored.signOut()
    }

    func testSigningInAgainAfterSignOutRaisesTheFlagAgain() {
        let session = makeStore()
        session.signIn(token: "t", user: user)
        _ = session.consumeJustSignedIn()

        session.signOut()
        session.signIn(token: "t2", user: user)

        XCTAssertTrue(session.consumeJustSignedIn(), "a second sign-in is still a sign-in")
        session.signOut()
    }
}
