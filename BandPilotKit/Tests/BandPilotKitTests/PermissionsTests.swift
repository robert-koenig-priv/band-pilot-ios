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

extension PermissionsTests {
    /// Media files use a wider rule than song editing, matching the backend's canManageMediaFiles.
    func testUploadingMediaIsOpenToPlainMembersButNotGuests() {
        // a plain MEMBER must be able to upload, or the "singer's version of the lead sheet" case --
        // the whole reason the owner tag exists -- is impossible
        XCTAssertTrue(Permissions.canUploadMedia(.member))
        XCTAssertTrue(Permissions.canUploadMedia(.editor))
        XCTAssertTrue(Permissions.canUploadMedia(.admin))
        XCTAssertTrue(Permissions.canUploadMedia(.globalAdmin))
        // GUEST is documented read-only; writing files while unable to rate a song would be incoherent
        XCTAssertFalse(Permissions.canUploadMedia(.guest))
        XCTAssertFalse(Permissions.canUploadMedia(nil))
    }

    func testDeletingAFileFollowsTheSameRuleBecauseThereIsNoPerFileACL() {
        XCTAssertTrue(Permissions.canDeleteMediaFile(.member))
        XCTAssertFalse(Permissions.canDeleteMediaFile(.guest))
    }
}
