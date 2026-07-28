import XCTest
@testable import BandPilotKit

/// Opt-in end-to-end test of the rehearsal WRITE path. Creates a throwaway rehearsal, adds/removes
/// a song, then deletes it (self-cleaning). Run with:
///   BP_LIVE=1 BP_EMAIL=… BP_PASSWORD=… swift test --filter LiveRehearsalTests
final class LiveRehearsalTests: XCTestCase {
    @MainActor final class TestTokenStore: TokenProviding {
        var token: String?
        func handleUnauthorized() { token = nil }
    }

    func testCreateAddRemoveDelete() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["BP_LIVE"] == "1", "set BP_LIVE=1 (+ BP_EMAIL/BP_PASSWORD) to run")
        let email = try XCTUnwrap(env["BP_EMAIL"])
        let password = try XCTUnwrap(env["BP_PASSWORD"])

        let api = APIClient(baseURL: URL(string: "http://localhost:8080")!)
        let store = await TestTokenStore()
        await api.setTokenProvider(store)
        let login = try await api.send(.login(.init(email: email, password: password)))
        await MainActor.run { store.token = login.accessToken }

        let bands = try await api.send(.bands)
        let bandId = try XCTUnwrap(bands.first { $0.securityRole == .admin || $0.securityRole == .editor }?.id
                                   ?? bands.first?.id)
        let catalog = try await api.send(.songsWithRatings(bandId: bandId))
        let firstSong = try XCTUnwrap(catalog.first)

        // create (far-future so it never collides with real planning)
        let plannedAt = "2099-01-01T20:00:00"
        let created = try await api.send(.createRehearsal(bandId: bandId, .init(plannedAt: plannedAt)))
        XCTAssertEqual(created.plannedAt, plannedAt)

        defer {
            // best-effort cleanup even if an assertion fails mid-test
            Task { _ = try? await api.send(.deleteRehearsal(bandId: bandId, id: created.id)) }
        }

        // add a song
        let added = try await api.send(.addRehearsalSong(bandId: bandId, rehearsalId: created.id, .init(songId: firstSong.id)))
        XCTAssertEqual(added.songId, firstSong.id)

        var detail = try await api.send(.rehearsalDetail(bandId: bandId, id: created.id))
        XCTAssertEqual(detail.songs.count, 1)

        // remove the song
        _ = try await api.send(.removeRehearsalSong(bandId: bandId, rehearsalId: created.id, songRowId: added.id))
        detail = try await api.send(.rehearsalDetail(bandId: bandId, id: created.id))
        XCTAssertTrue(detail.songs.isEmpty)

        // delete the rehearsal
        _ = try await api.send(.deleteRehearsal(bandId: bandId, id: created.id))
        let remaining = try await api.send(.rehearsals(bandId: bandId))
        XCTAssertFalse(remaining.contains { $0.id == created.id }, "rehearsal should be gone after delete")
    }
}
