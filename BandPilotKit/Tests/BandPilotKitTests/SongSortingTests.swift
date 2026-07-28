import XCTest
@testable import BandPilotKit

final class SongSortingTests: XCTestCase {
    private func song(_ id: Int, _ name: String, _ artist: String?, _ status: SongStatus, _ avg: Double) -> Song {
        Song(id: id, bandId: 1, name: name, artist: artist, status: status, averageRating: avg)
    }

    func testPracticeOrderByStatusThenRatingDesc() {
        let songs = [
            song(1, "A", "x", .readyForStage, 5.0),
            song(2, "B", "x", .needPractice, 2.0),
            song(3, "C", "x", .needPractice, 4.0),
            song(4, "D", "x", .suggested, 1.0),
        ]
        let ordered = SongSorting.sorted(songs, by: .practiceOrder).map(\.id)
        // NEED_PRACTICE (rating desc: 3 then 2) → SUGGESTED (4) → READY_FOR_STAGE (1)
        XCTAssertEqual(ordered, [3, 2, 4, 1])
    }

    func testSortByNameCaseInsensitive() {
        let songs = [song(1, "banana", "x", .suggested, 0), song(2, "Apple", "x", .suggested, 0)]
        XCTAssertEqual(SongSorting.sorted(songs, by: .name).map(\.id), [2, 1])
    }

    func testSortByArtistNilLast() {
        let songs = [song(1, "A", nil, .suggested, 0), song(2, "B", "Zed", .suggested, 0), song(3, "C", "Alpha", .suggested, 0)]
        // "" (nil) sorts first ascending, then Alpha, then Zed
        XCTAssertEqual(SongSorting.sorted(songs, by: .artist).map(\.id), [1, 3, 2])
    }

    func testFilterByStatus() {
        let songs = [song(1, "A", "x", .suggested, 0), song(2, "B", "x", .readyForStage, 0)]
        XCTAssertEqual(SongSorting.filtered(songs, status: .readyForStage).map(\.id), [2])
        XCTAssertEqual(SongSorting.filtered(songs, status: nil).count, 2)
    }
}
