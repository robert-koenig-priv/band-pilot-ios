import XCTest
@testable import BandPilotKit

/// Decoding tests using real JSON captured from the live backend, to lock the
/// Codable models to the actual API shapes (extra keys like band-members'
/// birthday/gender/roles must be tolerated).
final class DecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder.decode(type, from: Data(json.utf8))
    }

    func testLoginResponse() throws {
        let json = """
        {"accessToken":"abc.def.ghi","tokenType":"Bearer","expiresIn":86400,
         "user":{"id":2,"email":"robert.koenig2@gmail.com","firstName":"Robert","lastName":"König","emailVerified":true}}
        """
        let r = try decode(LoginResponse.self, json)
        XCTAssertEqual(r.expiresIn, 86400)
        XCTAssertEqual(r.user.id, 2)
        XCTAssertEqual(r.user.fullName, "Robert König")
        XCTAssertTrue(r.user.emailVerified)
    }

    func testBandWithSecurityRoleAndNullHomepage() throws {
        let json = """
        {"id":1,"name":"Robert & Friends","tagline":"Unplugged at its best",
         "description":"Unplugged Songs in kleinem Rahmen","location":"Karlsruhe",
         "founded":"2019-06-01","homepage":null,"securityRole":"ADMIN"}
        """
        let b = try decode(Band.self, json)
        XCTAssertEqual(b.id, 1)
        XCTAssertNil(b.homepage)
        XCTAssertEqual(b.securityRole, .admin)
    }

    func testMembership() throws {
        let json = """
        {"bandMemberId":6,"nickName":"Joe","userId":7,"email":"joe@test.com",
         "firstName":"Jürgen","lastName":"TBD","securityRole":"MEMBER"}
        """
        let m = try decode(Membership.self, json)
        XCTAssertEqual(m.bandMemberId, 6)
        XCTAssertEqual(m.userId, 7)
        XCTAssertEqual(m.securityRole, .member)
    }

    func testBandMemberToleratesExtraKeys() throws {
        // The real band-members payload also carries birthday/gender/roles/started — must be ignored.
        let json = """
        {"id":6,"bandId":2,"nickName":"Joe","birthday":null,"gender":"MALE",
         "roles":[{"id":19,"bandId":2,"name":"Lead Guitar"}],"started":null}
        """
        let bm = try decode(BandMember.self, json)
        XCTAssertEqual(bm.id, 6)
        XCTAssertEqual(bm.nickName, "Joe")
    }

    func testFlag() throws {
        let json = ##"{"id":5,"bandId":2,"meaning":"Acoustic","description":"Acoustic guitar used in the song.","color":"#936201"}"##
        let f = try decode(Flag.self, json)
        XCTAssertEqual(f.color, "#936201")
        XCTAssertEqual(f.meaning, "Acoustic")
    }

    func testSongWithRatings() throws {
        let json = """
        {"id":8,"bandId":2,"name":"All Right Now","artist":"Free","year":"1970",
         "originalKey":"A","key":null,"originalBpm":120,"bpm":null,"durationSec":331,
         "comments":null,"status":"READY_FOR_STAGE","averageRating":3.0,
         "ratings":[{"id":46,"songId":8,"bandMemberId":3,"rating":3}],"flags":[]}
        """
        let s = try decode(SongWithRatings.self, json)
        XCTAssertEqual(s.id, 8)
        XCTAssertNil(s.key)
        XCTAssertEqual(s.status, .readyForStage)
        XCTAssertEqual(s.ratings.count, 1)
        XCTAssertTrue(s.flags.isEmpty)
        // projection to the plain song keeps the server average
        XCTAssertEqual(s.song.averageRating, 3.0, accuracy: 0.0001)
        XCTAssertEqual(s.song.durationSec, 331)
    }

    func testSongDefaultsAverageWhenAbsent() throws {
        // The plain song PUT response omits averageRating → must default to 0.0.
        let json = """
        {"id":8,"bandId":2,"name":"X","artist":"Y","year":null,"originalKey":null,"key":null,
         "originalBpm":null,"bpm":null,"durationSec":null,"comments":null,"status":"SUGGESTED"}
        """
        let s = try decode(Song.self, json)
        XCTAssertEqual(s.averageRating, 0.0)
        XCTAssertEqual(s.status, .suggested)
    }

    func testSongFlagEffectiveColor() throws {
        let withOverride = ##"{"id":1,"songId":8,"flagId":5,"meaning":"Acoustic","description":null,"meaningDetails":null,"color":"#FF0000","flagColor":"#936201","bandMemberId":null}"##
        XCTAssertEqual(try decode(SongFlag.self, withOverride).effectiveColor, "#FF0000")
        let noOverride = ##"{"id":1,"songId":8,"flagId":5,"meaning":"Acoustic","description":null,"meaningDetails":null,"color":null,"flagColor":"#936201","bandMemberId":null}"##
        XCTAssertEqual(try decode(SongFlag.self, noOverride).effectiveColor, "#936201")
    }
}
