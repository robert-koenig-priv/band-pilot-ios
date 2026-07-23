import XCTest
@testable import BandPilotKit

final class RehearsalTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testDecodeRehearsalList() throws {
        let json = """
        [{"id":16,"bandId":2,"plannedAt":"2026-07-28T18:30:00","status":"PLANNED"},
         {"id":12,"bandId":2,"plannedAt":"2026-07-21T18:30:00","status":"PLANNED"}]
        """
        let list = try decoder.decode([Rehearsal].self, from: Data(json.utf8))
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].status, .planned)
    }

    func testDecodeRehearsalDetail() throws {
        let json = """
        {"id":16,"bandId":2,"plannedAt":"2026-07-28T18:30:00","status":"PLANNED",
         "songs":[{"id":333,"rehearsalId":16,"bandSongId":36,"songName":"Honky Tonk Women","artist":"The Rolling Stones","ordering":0,"details":null},
                  {"id":335,"rehearsalId":16,"bandSongId":24,"songName":"Are You Gonna Be My Girl","artist":"Jet","ordering":2,"details":null}],
         "missingMembers":[]}
        """
        let detail = try decoder.decode(RehearsalDetail.self, from: Data(json.utf8))
        XCTAssertEqual(detail.songs.count, 2)
        XCTAssertEqual(detail.songs[0].songName, "Honky Tonk Women")
        XCTAssertEqual(detail.songs[1].ordering, 2)
        XCTAssertTrue(detail.missingMembers.isEmpty)
        XCTAssertEqual(detail.summary.id, 16)
    }

    // MARK: - Scheduling heuristic

    private func reh(_ id: Int, _ date: String, _ status: RehearsalStatus = .planned) -> Rehearsal {
        Rehearsal(id: id, bandId: 1, plannedAt: date, status: status)
    }
    private var now: Date { RehearsalScheduling.date(from: "2026-07-25T12:00:00")! }

    func testDefaultPicksEarliestUpcoming() {
        let list = RehearsalScheduling.sorted([
            reh(1, "2026-07-20T18:00:00"),
            reh(2, "2026-07-28T18:00:00"),
            reh(3, "2026-08-05T18:00:00"),
        ])
        XCTAssertEqual(RehearsalScheduling.defaultRehearsalId(list, now: now), 2)
    }

    func testDefaultFallsBackToMostRecentPast() {
        let list = RehearsalScheduling.sorted([
            reh(1, "2026-07-10T18:00:00"),
            reh(2, "2026-07-20T18:00:00"),
        ])
        XCTAssertEqual(RehearsalScheduling.defaultRehearsalId(list, now: now), 2)
    }

    func testDefaultSkipsCanceled() {
        let list = RehearsalScheduling.sorted([
            reh(1, "2026-07-20T18:00:00"),
            reh(2, "2026-07-28T18:00:00", .canceled),
            reh(3, "2026-08-05T18:00:00"),
        ])
        // earliest upcoming non-canceled is #3 (the 28th is canceled)
        XCTAssertEqual(RehearsalScheduling.defaultRehearsalId(list, now: now), 3)
    }

    func testDefaultNilWhenAllCanceledOrEmpty() {
        XCTAssertNil(RehearsalScheduling.defaultRehearsalId([], now: now))
        let allCanceled = [reh(1, "2026-07-28T18:00:00", .canceled)]
        XCTAssertNil(RehearsalScheduling.defaultRehearsalId(allCanceled, now: now))
    }

    func testIsoRoundTrip() {
        let iso = "2026-07-28T18:30:00"
        let date = RehearsalScheduling.date(from: iso)
        XCTAssertNotNil(date)
        XCTAssertEqual(RehearsalScheduling.iso(from: date!), iso)
    }
}
