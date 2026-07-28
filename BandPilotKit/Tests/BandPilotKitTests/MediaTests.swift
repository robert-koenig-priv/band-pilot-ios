import XCTest
@testable import BandPilotKit

final class MediaTests: XCTestCase {
    func testDecodeMediaLinks() throws {
        let json = """
        [{"id":21,"songId":8,"name":"Studio","mediaType":"YOUTUBE","url":"https://www.youtube.com/watch?v=lSdBtoIIYT4"},
         {"id":13,"songId":5,"name":"Backing Vocal","mediaType":"AUDIO","url":"https://example.com/x.mp3"},
         {"id":9,"songId":12,"name":"Spotify","mediaType":"SPOTIFY","url":"https://open.spotify.com/track/abc"}]
        """
        let links = try JSONDecoder().decode([MediaLink].self, from: Data(json.utf8))
        XCTAssertEqual(links.count, 3)
        XCTAssertEqual(links[0].mediaType, .youtube)
        XCTAssertTrue(links[0].mediaType.playsInApp)
        XCTAssertFalse(links[2].mediaType.playsInApp)
    }

    func testYouTubeVideoIdParsing() {
        XCTAssertEqual(YouTube.videoId(from: "https://www.youtube.com/watch?v=lSdBtoIIYT4"), "lSdBtoIIYT4")
        XCTAssertEqual(YouTube.videoId(from: "https://youtu.be/dQw4w9WgXcQ"), "dQw4w9WgXcQ")
        XCTAssertEqual(YouTube.videoId(from: "https://m.youtube.com/watch?v=abc12&t=30s"), "abc12")
        XCTAssertEqual(YouTube.videoId(from: "https://www.youtube.com/shorts/XyZ123abc_-"), "XyZ123abc_-")
        // list/radio param preserved on the watch id
        XCTAssertEqual(YouTube.videoId(from: "https://www.youtube.com/watch?v=OEPvv9pjIoQ&list=RD"), "OEPvv9pjIoQ")
        XCTAssertNil(YouTube.videoId(from: "https://open.spotify.com/track/abc"))
        XCTAssertNil(YouTube.videoId(from: "not a url at all"))
    }

    func testEmbedURL() {
        XCTAssertEqual(YouTube.embedURL("abc123")?.absoluteString, "https://www.youtube.com/embed/abc123?playsinline=1&rel=0")
    }
}
