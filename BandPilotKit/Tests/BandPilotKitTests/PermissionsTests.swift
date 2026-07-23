import XCTest
@testable import BandPilotKit

final class PermissionsTests: XCTestCase {
    func testIsAdmin() {
        XCTAssertTrue(Permissions.isAdmin(.admin))
        XCTAssertTrue(Permissions.isAdmin(.globalAdmin))
        XCTAssertFalse(Permissions.isAdmin(.editor))
        XCTAssertFalse(Permissions.isAdmin(.member))
        XCTAssertFalse(Permissions.isAdmin(nil))
    }

    func testCanEditSongs() {
        XCTAssertTrue(Permissions.canEditSongs(.admin))
        XCTAssertTrue(Permissions.canEditSongs(.editor))
        XCTAssertFalse(Permissions.canEditSongs(.globalAdmin)) // matches Android: SONG_MANAGER_ROLES = {ADMIN, EDITOR}
        XCTAssertFalse(Permissions.canEditSongs(.member))
        XCTAssertFalse(Permissions.canEditSongs(.guest))
    }

    func testCanVoteForSelfOnlyUnlessAdmin() {
        XCTAssertTrue(Permissions.canVoteFor(memberId: 7, myBandMemberId: 7, isAdmin: false))
        XCTAssertFalse(Permissions.canVoteFor(memberId: 8, myBandMemberId: 7, isAdmin: false))
        XCTAssertTrue(Permissions.canVoteFor(memberId: 8, myBandMemberId: 7, isAdmin: true))
        XCTAssertFalse(Permissions.canVoteFor(memberId: 8, myBandMemberId: nil, isAdmin: false))
    }
}
