import XCTest
@testable import BandPilotKit

final class MediaFileDecodingTests: XCTestCase {

    private let decoder = JSONDecoder()

    private func decodeFile(_ json: String) throws -> MediaFile {
        try decoder.decode(MediaFile.self, from: Data(json.utf8))
    }

    private var fullJSON: String {
        """
        {"id":7,"bandId":1,"bandSongId":3,"name":"Lead sheet","kind":"SHEET",
         "mimeType":"application/pdf","sizeBytes":123456,"sha256":"abc","ownerBandMemberId":9,
         "uploadState":"READY","takedownState":"ACTIVE","uploadedByUserId":2,
         "uploadedAt":"2026-07-25T12:00:00Z","createdAt":"2026-07-25T11:59:00Z",
         "deletedAt":null,"downloadable":true}
        """
    }

    func testDecodesTheFullPayload() throws {
        let file = try decodeFile(fullJSON)

        XCTAssertEqual(file.id, 7)
        XCTAssertEqual(file.kind, .sheet)
        XCTAssertEqual(file.sizeBytes, 123_456)
        XCTAssertEqual(file.ownerBandMemberId, 9)
        XCTAssertTrue(file.downloadable)
    }

    func testAnUnknownKindDoesNotBreakDecoding() throws {
        // A strict enum would throw here, and one unrecognised value from a newer backend would blank the
        // entire file list — a guaranteed field bug while the backend is still evolving.
        let file = try decodeFile(fullJSON.replacingOccurrences(of: "\"SHEET\"", with: "\"TABLATURE\""))

        XCTAssertEqual(file.kind, .unknown("TABLATURE"))
        XCTAssertEqual(file.kind.label, "Tablature", "an unknown kind should still be presentable")
    }

    func testSizeSurvivesValuesBeyondInt32() throws {
        // sizeBytes is Int64: a 3 GB video would overflow a 32-bit field
        let file = try decodeFile(fullJSON.replacingOccurrences(of: "123456", with: "3221225472"))
        XCTAssertEqual(file.sizeBytes, 3_221_225_472)
    }

    func testViewerIsChosenByMimeTypeNotKind() throws {
        // the case this exists for: a photographed chord chart is a SHEET carrying image/jpeg, and PDFKit
        // handed a JPEG draws a blank page
        let photoSheet = try decodeFile(
            fullJSON.replacingOccurrences(of: "\"application/pdf\"", with: "\"image/jpeg\"")
        )
        XCTAssertEqual(photoSheet.kind, .sheet)
        XCTAssertEqual(photoSheet.viewer, .image)

        let pdfSheet = try decodeFile(fullJSON)
        XCTAssertEqual(pdfSheet.viewer, .pdf)
    }

    // MARK: - Transfer envelope

    func testEnvelopeToleratesAbsentHeaders() throws {
        // S3 carries auth in the query string and sends no headers at all
        let envelope = try decoder.decode(
            TransferEnvelope.self,
            from: Data(#"{"method":"GET","url":"https://b/o","expiresAt":"2099-01-01T00:00:00Z"}"#.utf8)
        )

        XCTAssertEqual(envelope.headers, [:])
        XCTAssertTrue(envelope.isUsable())
    }

    func testEnvelopeCarriesHeadersWhenPresent() throws {
        let json = """
        {"method":"PUT","url":"https://b/o","expiresAt":"2099-01-01T00:00:00Z",
         "headers":{"Content-Type":"audio/mpeg","Content-MD5":"kA2V"}}
        """
        let envelope = try decoder.decode(TransferEnvelope.self, from: Data(json.utf8))

        XCTAssertEqual(envelope.headers["Content-Type"], "audio/mpeg")
        XCTAssertEqual(envelope.headers["Content-MD5"], "kA2V")
    }

    func testAnEnvelopeInsideTheSafetyMarginCountsAsExpired() {
        // starting a transfer seconds before the URL dies would fail mid-flight
        let almostGone = TransferEnvelope(
            method: "GET", url: URL(string: "https://b/o")!,
            expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(10))
        )
        XCTAssertFalse(almostGone.isUsable())
    }

    func testAnUnparseableExpiryCountsAsExpired() {
        // guessing that a credential is still valid is the wrong way to be wrong
        let nonsense = TransferEnvelope(
            method: "GET", url: URL(string: "https://b/o")!, expiresAt: "not-a-date"
        )
        XCTAssertFalse(nonsense.isUsable())
    }

    func testFractionalSecondsParse() {
        // Jackson's default Instant serialization emits them, and ISO8601DateFormatter fails on them
        // unless told to expect them — getting this wrong makes every envelope look expired
        XCTAssertNotNil(ISO8601.date(from: "2026-07-25T12:00:00.123Z"))
        XCTAssertNotNil(ISO8601.date(from: "2026-07-25T12:00:00Z"))
        XCTAssertNotNil(ISO8601.date(from: "2026-07-25T14:00:00+02:00"))
        XCTAssertNil(ISO8601.date(from: "yesterday"))
    }

    // MARK: - Owner filter

    func testMineIncludesBandOwnedFiles() throws {
        let mine = try decodeFile(fullJSON.replacingOccurrences(of: "\"ownerBandMemberId\":9", with: "\"ownerBandMemberId\":5"))
        let bandOwned = try decodeFile(fullJSON.replacingOccurrences(of: "\"ownerBandMemberId\":9", with: "\"ownerBandMemberId\":null"))
        let someoneElse = try decodeFile(fullJSON)

        // "Mine" must never hide band-level material — only another member's personal variant
        XCTAssertTrue(MediaOwnerFilter.mineAndBand.includes(mine, myBandMemberId: 5))
        XCTAssertTrue(MediaOwnerFilter.mineAndBand.includes(bandOwned, myBandMemberId: 5))
        XCTAssertFalse(MediaOwnerFilter.mineAndBand.includes(someoneElse, myBandMemberId: 5))
        XCTAssertTrue(MediaOwnerFilter.everyone.includes(someoneElse, myBandMemberId: 5))
    }

    func testALoginWithNoRosterEntrySeesEverything() throws {
        // such a user has no "mine", so filtering would show them an inexplicably short list
        let someoneElse = try decodeFile(fullJSON)
        XCTAssertTrue(MediaOwnerFilter.mineAndBand.includes(someoneElse, myBandMemberId: nil))
    }
}
