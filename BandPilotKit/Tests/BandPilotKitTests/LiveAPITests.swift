import XCTest
@testable import BandPilotKit

/// End-to-end smoke test against a running backend. Opt-in: set
///   BP_LIVE=1 BP_EMAIL=… BP_PASSWORD=… swift test
/// Credentials come from the environment so no secret is ever committed.
final class LiveAPITests: XCTestCase {
    @MainActor final class TestTokenStore: TokenProviding {
        var token: String?
        func handleUnauthorized() { token = nil }
    }

    func testLoginBandsAndSongs() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["BP_LIVE"] == "1", "set BP_LIVE=1 (plus BP_EMAIL/BP_PASSWORD) to run the live smoke test")
        let email = try XCTUnwrap(env["BP_EMAIL"])
        let password = try XCTUnwrap(env["BP_PASSWORD"])

        let api = APIClient(baseURL: URL(string: "http://localhost:8080")!)
        let store = await TestTokenStore()
        await api.setTokenProvider(store)

        let login = try await api.send(.login(.init(email: email, password: password)))
        XCTAssertFalse(login.accessToken.isEmpty)
        await MainActor.run { store.token = login.accessToken }

        let bands = try await api.send(.bands)
        XCTAssertFalse(bands.isEmpty, "expected at least one band")

        let bandId = bands[0].id
        let members = try await api.send(.members(bandId: bandId))
        XCTAssertTrue(members.contains { $0.userId == login.user.id }, "caller should be a member")

        let songs = try await api.send(.songsWithRatings(bandId: bandId))
        XCTAssertFalse(songs.isEmpty, "expected songs in the first band")
        // Local average matches the server-computed one for a sampled song.
        if let sample = songs.first(where: { !$0.ratings.isEmpty }) {
            XCTAssertEqual(RatingMath.averageRatingOf(sample.ratings), sample.averageRating, accuracy: 0.0001,
                           "client RatingMath must match the server average")
        }
    }
}
