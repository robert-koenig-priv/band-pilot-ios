import XCTest
@testable import BandPilotKit

final class SongSortingTests: XCTestCase {
    private func song(
        _ id: Int, _ name: String, _ artist: String?, _ status: SongStatus, _ avg: Double
    ) -> Song {
        Song(id: id, bandId: 1, name: name, artist: artist, status: status, averageRating: avg)
    }

    private func avg(_ s: Song) -> Double { s.averageRating }

    func testSortByNameCaseInsensitive() {
        let songs = [song(1, "banana", "x", .suggested, 0), song(2, "Apple", "x", .suggested, 0)]
        XCTAssertEqual(SongSorting.sorted(songs, by: .name, descending: false, ratingOf: avg).map(\.id), [2, 1])
    }

    func testSortByArtistThenName() {
        let songs = [
            song(1, "B", "Zed", .suggested, 0),
            song(2, "A", "Alpha", .suggested, 0),
            song(3, "C", "Alpha", .suggested, 0),
        ]
        XCTAssertEqual(
            SongSorting.sorted(songs, by: .artist, descending: false, ratingOf: avg).map(\.id),
            [2, 3, 1]
        )
    }

    /// Android's rating comparator is rating-descending with name as the tiebreak, and `descending`
    /// then reverses the whole thing. So the un-reversed order is highest-rated first.
    func testRatingSortIsHighestFirstWithNameTiebreak() {
        let songs = [
            song(1, "B", "x", .suggested, 4.0),
            song(2, "A", "x", .suggested, 4.0),
            song(3, "C", "x", .suggested, 5.0),
        ]
        XCTAssertEqual(
            SongSorting.sorted(songs, by: .rating, descending: false, ratingOf: avg).map(\.id),
            [3, 2, 1]
        )
    }

    func testDescendingReversesTheOrder() {
        let songs = [song(1, "A", "x", .suggested, 0), song(2, "B", "x", .suggested, 0)]
        XCTAssertEqual(
            SongSorting.sorted(songs, by: .name, descending: true, ratingOf: avg).map(\.id),
            [2, 1]
        )
    }

    /// The rating is injected because two different ratings are in play — the band average and the
    /// member's own vote — and the sort must follow whichever the Rating display chip is showing.
    func testSortUsesTheInjectedRating() {
        let songs = [song(1, "A", "x", .suggested, 1.0), song(2, "B", "x", .suggested, 5.0)]
        let inverted: (Song) -> Double = { 6 - $0.averageRating }
        XCTAssertEqual(
            SongSorting.sorted(songs, by: .rating, descending: false, ratingOf: inverted).map(\.id),
            [1, 2]
        )
    }

    func testFilterByStatus() {
        let songs = [song(1, "A", "x", .suggested, 0), song(2, "B", "x", .readyForStage, 0)]
        let only = SongSorting.filtered(songs, status: .readyForStage, flagId: nil, flags: [:], search: "")
        XCTAssertEqual(only.map(\.id), [2])
        XCTAssertEqual(
            SongSorting.filtered(songs, status: nil, flagId: nil, flags: [:], search: "").count, 2
        )
    }

    func testFilterByFlagId() {
        let songs = [song(1, "A", "x", .suggested, 0), song(2, "B", "x", .suggested, 0)]
        let flags: [Int: [SongFlag]] = [
            1: [SongFlag(id: 10, songId: 1, flagId: 7, meaning: "Solo", description: nil,
                         meaningDetails: nil, color: nil, flagColor: "#FF0000", bandMemberId: nil)]
        ]
        let only = SongSorting.filtered(songs, status: nil, flagId: 7, flags: flags, search: "")
        XCTAssertEqual(only.map(\.id), [1])
    }

    func testSearchMatchesNameOrArtistCaseInsensitively() {
        let songs = [song(1, "Africa", "Toto", .suggested, 0), song(2, "Bitch", "Meredith", .suggested, 0)]
        XCTAssertEqual(
            SongSorting.filtered(songs, status: nil, flagId: nil, flags: [:], search: "TOT").map(\.id),
            [1]
        )
        XCTAssertEqual(
            SongSorting.filtered(songs, status: nil, flagId: nil, flags: [:], search: "bit").map(\.id),
            [2]
        )
    }
}
