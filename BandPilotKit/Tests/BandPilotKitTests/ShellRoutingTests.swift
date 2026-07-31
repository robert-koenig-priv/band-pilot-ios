import XCTest
@testable import BandPilotKit

final class ShellRoutingTests: XCTestCase {
    func testBandsIsTheEmptyPath() {
        XCTAssertEqual(ShellRouting.path(to: nil), [])
    }

    func testEachDestinationReplacesTheWholePath() {
        XCTAssertEqual(ShellRouting.path(to: .songs(bandId: 7)), [.songs(bandId: 7)])
        XCTAssertEqual(ShellRouting.path(to: .rehearsals(bandId: 7)), [.rehearsals(bandId: 7)])
    }

    /// The reason this type exists at all. Walking Songs → Rehearsal → Songs from the drawer must
    /// leave one entry, not three: the back chevron has to keep meaning "Bands" however you got here.
    func testRepeatedDrawerNavigationNeverGrowsThePath() {
        var path = ShellRouting.path(to: .songs(bandId: 7))
        path = ShellRouting.path(to: .rehearsals(bandId: 7))
        path = ShellRouting.path(to: .songs(bandId: 7))
        XCTAssertEqual(path, [.songs(bandId: 7)])
    }

    func testSelectedIsNilAtTheRootAndTheLastRouteOtherwise() {
        XCTAssertNil(ShellRouting.selected(in: []))
        XCTAssertEqual(ShellRouting.selected(in: [.rehearsals(bandId: 3)]), .rehearsals(bandId: 3))
    }

    func testSwitchingBandKeepsThePathOneDeep() {
        XCTAssertEqual(ShellRouting.path(to: .songs(bandId: 9)), [.songs(bandId: 9)])
    }
}
