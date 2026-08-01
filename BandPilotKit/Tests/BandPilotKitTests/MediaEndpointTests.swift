import XCTest
@testable import BandPilotKit

/// Path strings live in the route factories, so this is where a typo in one gets caught — the
/// alternative is discovering it as a 404 against a live backend.
final class MediaEndpointTests: XCTestCase {
    func testBandWideMediaLinksEndpointShape() {
        let endpoint = Endpoint<[MediaLink]>.mediaLinks(bandId: 42)
        XCTAssertEqual(endpoint.path, "api/bands/42/media-links")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertTrue(endpoint.requiresAuth)
    }

    /// The per-song route stays: it is the fallback after a failed bulk read, and every write path
    /// still addresses a single song.
    func testPerSongMediaLinksEndpointIsUnchanged() {
        let endpoint = Endpoint<[MediaLink]>.mediaLinks(bandId: 42, songId: 7)
        XCTAssertEqual(endpoint.path, "api/bands/42/songs/7/media-links")
        XCTAssertEqual(endpoint.method, .get)
    }
}
