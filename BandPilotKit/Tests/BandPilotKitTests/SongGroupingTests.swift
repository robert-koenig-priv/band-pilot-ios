import XCTest
@testable import BandPilotKit

final class SongGroupingTests: XCTestCase {
    private func song(
        _ id: Int, _ name: String, _ artist: String? = "x", _ year: String? = nil,
        _ status: SongStatus = .suggested, _ avg: Double = 0
    ) -> Song {
        Song(id: id, bandId: 1, name: name, artist: artist, year: year, status: status, averageRating: avg)
    }

    private func flag(_ id: Int, _ songId: Int, _ flagId: Int, _ meaning: String) -> SongFlag {
        SongFlag(id: id, songId: songId, flagId: flagId, meaning: meaning, description: nil,
                 meaningDetails: nil, color: nil, flagColor: "#FF0000", bandMemberId: nil)
    }

    // MARK: keys

    func testStatusKeyIsTheStatus() {
        XCTAssertEqual(
            SongGrouping.groupKeys(for: song(1, "A", "x", nil, .needPractice), by: .status,
                                   flags: [], flagOrder: [], rating: 0),
            ["NEED_PRACTICE"]
        )
    }

    func testArtistKeyTrimsAndFallsBackToUnknown() {
        XCTAssertEqual(
            SongGrouping.groupKeys(for: song(1, "A", "  Toto "), by: .artist, flags: [], flagOrder: [], rating: 0),
            ["Toto"]
        )
        XCTAssertEqual(
            SongGrouping.groupKeys(for: song(2, "B", "   "), by: .artist, flags: [], flagOrder: [], rating: 0),
            [SongGrouping.unknownArtistKey]
        )
        XCTAssertEqual(
            SongGrouping.groupKeys(for: song(3, "C", nil), by: .artist, flags: [], flagOrder: [], rating: 0),
            [SongGrouping.unknownArtistKey]
        )
    }

    func testDecadeKeyFloorsToTheDecade() {
        XCTAssertEqual(
            SongGrouping.groupKeys(for: song(1, "A", "x", "1987"), by: .decade, flags: [], flagOrder: [], rating: 0),
            ["1980"]
        )
        XCTAssertEqual(
            SongGrouping.groupKeys(for: song(2, "B", "x", nil), by: .decade, flags: [], flagOrder: [], rating: 0),
            [SongGrouping.unknownYearKey]
        )
        // A full ISO date must not be read as a year — the backend can answer "1989-06-01".
        XCTAssertEqual(
            SongGrouping.groupKeys(for: song(3, "C", "x", "1989-06-01"), by: .decade,
                                   flags: [], flagOrder: [], rating: 0),
            ["1980"]
        )
    }

    func testRatingKeyBuckets() {
        func key(_ rating: Double) -> String {
            SongGrouping.groupKeys(for: song(1, "A"), by: .rating, flags: [], flagOrder: [], rating: rating)[0]
        }
        XCTAssertEqual(key(-1), SongGrouping.vetoedKey)
        XCTAssertEqual(key(0), SongGrouping.unratedKey)
        XCTAssertEqual(key(4.4), "4")
        XCTAssertEqual(key(4.5), "5")
        XCTAssertEqual(key(5), "5")
    }

    func testFlagKeysAreMultiMembershipInCatalogOrder() {
        let songFlags = [flag(1, 1, 9, "Zed"), flag(2, 1, 3, "Alpha")]
        XCTAssertEqual(
            SongGrouping.groupKeys(for: song(1, "A"), by: .flag, flags: songFlags,
                                   flagOrder: [3, 9], rating: 0),
            ["3", "9"]
        )
    }

    /// Deliberate, and pinned so nobody "fixes" it: a song with no flag belongs to no group and
    /// therefore vanishes from the list while grouped by Flag. Android behaves the same way.
    func testSongWithNoFlagBelongsToNoGroup() {
        XCTAssertEqual(
            SongGrouping.groupKeys(for: song(1, "A"), by: .flag, flags: [], flagOrder: [3], rating: 0),
            []
        )
    }

    // MARK: ordering

    func testStatusGroupsUseThePracticeChipOrder() {
        let songs = [
            song(1, "A", "x", nil, .suggested), song(2, "B", "x", nil, .readyForStage),
            song(3, "C", "x", nil, .needPractice),
        ]
        let groups = SongGrouping.groupSongs(songs, by: .status, flagsInUse: []) {
            SongGrouping.groupKeys(for: $0, by: .status, flags: [], flagOrder: [], rating: 0)
        }
        XCTAssertEqual(groups.map(\.key), ["READY_FOR_STAGE", "NEED_PRACTICE", "SUGGESTED"])
    }

    func testArtistGroupsByCountDescendingThenAlphabetical() {
        let songs = [
            song(1, "A", "Solo"), song(2, "B", "Duo"), song(3, "C", "Duo"),
            song(4, "D", nil),
        ]
        let groups = SongGrouping.groupSongs(songs, by: .artist, flagsInUse: []) {
            SongGrouping.groupKeys(for: $0, by: .artist, flags: [], flagOrder: [], rating: 0)
        }
        XCTAssertEqual(groups.map(\.key), ["Duo", "Solo", SongGrouping.unknownArtistKey])
    }

    func testDecadeGroupsAscendingWithUnknownLast() {
        let songs = [song(1, "A", "x", "1995"), song(2, "B", "x", nil), song(3, "C", "x", "1980")]
        let groups = SongGrouping.groupSongs(songs, by: .decade, flagsInUse: []) {
            SongGrouping.groupKeys(for: $0, by: .decade, flags: [], flagOrder: [], rating: 0)
        }
        XCTAssertEqual(groups.map(\.key), ["1980", "1990", SongGrouping.unknownYearKey])
    }

    func testRatingGroupsRunFiveDownThenUnratedThenVetoed() {
        let ratings: [Int: Double] = [1: 5, 2: 0, 3: -1, 4: 3]
        let songs = [song(1, "A"), song(2, "B"), song(3, "C"), song(4, "D")]
        let groups = SongGrouping.groupSongs(songs, by: .rating, flagsInUse: []) {
            SongGrouping.groupKeys(for: $0, by: .rating, flags: [], flagOrder: [],
                                   rating: ratings[$0.id] ?? 0)
        }
        XCTAssertEqual(groups.map(\.key), ["5", "3", SongGrouping.unratedKey, SongGrouping.vetoedKey])
    }

    // MARK: labels

    func testLabels() {
        XCTAssertEqual(SongGrouping.groupLabel(for: "NEED_PRACTICE", by: .status, flagsInUse: []), "Need practice")
        XCTAssertEqual(SongGrouping.groupLabel(for: SongGrouping.unknownArtistKey, by: .artist, flagsInUse: []), "Unknown artist")
        XCTAssertEqual(SongGrouping.groupLabel(for: "1980", by: .decade, flagsInUse: []), "1980s")
        XCTAssertEqual(SongGrouping.groupLabel(for: SongGrouping.unknownYearKey, by: .decade, flagsInUse: []), "Unknown year")
        XCTAssertEqual(SongGrouping.groupLabel(for: "5", by: .rating, flagsInUse: []), "5 Stars")
        XCTAssertEqual(SongGrouping.groupLabel(for: "1", by: .rating, flagsInUse: []), "1 Star")
        XCTAssertEqual(SongGrouping.groupLabel(for: SongGrouping.unratedKey, by: .rating, flagsInUse: []), "Not rated")
        XCTAssertEqual(SongGrouping.groupLabel(for: SongGrouping.vetoedKey, by: .rating, flagsInUse: []), "Vetoed")
    }

    // MARK: flagsInUse

    func testFlagsInUseIsDedupedAndSortedByMeaning() {
        let flags: [Int: [SongFlag]] = [
            1: [flag(1, 1, 9, "Zed"), flag(2, 1, 3, "alpha")],
            2: [flag(3, 2, 9, "Zed")],
        ]
        XCTAssertEqual(SongGrouping.flagsInUse(flags).map(\.id), [3, 9])
        XCTAssertEqual(SongGrouping.flagsInUse(flags).map(\.meaning), ["alpha", "Zed"])
    }
}
