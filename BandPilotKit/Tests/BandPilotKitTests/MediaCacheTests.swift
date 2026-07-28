import XCTest
@testable import BandPilotKit

/// The on-disk media cache.
///
/// Content-addressed: blobs are named by their own SHA-256, so verification is "does this file hash to
/// its own name" and the same bytes attached to two songs are stored once. The manifest holds only what
/// the offline UI needs and the filesystem cannot express, so losing it costs metadata, never bytes.
final class MediaCacheTests: XCTestCase {

    private var root: URL!
    private var cache: MediaCache!
    private var clock: Date!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mediacache-\(UUID().uuidString)")
        clock = Date(timeIntervalSince1970: 1_000_000)
        // an injected clock, because two files cached in the same instant have no defined LRU order
        cache = MediaCache(root: root, budgetBytes: 1000, now: { self.clock })
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func tick(_ seconds: TimeInterval = 1) { clock = clock.addingTimeInterval(seconds) }

    private func file(
        id: Int,
        bytes: Data,
        mime: String = "audio/mpeg",
        kind: MediaFileKind = .audio
    ) -> MediaFile {
        MediaFile(
            id: id, bandId: 1, songId: nil, name: "Track \(id)", kind: kind, mimeType: mime,
            sizeBytes: Int64(bytes.count), sha256: Digest.sha256Hex(of: bytes), ownerBandMemberId: nil,
            uploadState: .ready, takedownState: .active, uploadedByUserId: 1, uploadedAt: nil,
            createdAt: "", deletedAt: nil, downloadable: true
        )
    }

    /// simulate a finished download: write a temp file, then adopt it
    private func store(_ media: MediaFile, bytes: Data) throws -> URL {
        let temp = root.appendingPathComponent("incoming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try bytes.write(to: temp)
        tick()
        return try cache.adopt(temp, for: media)
    }

    func testStoredFileIsFoundAgain() throws {
        let bytes = Data("hello".utf8)
        let media = file(id: 7, bytes: bytes)
        _ = try store(media, bytes: bytes)

        let found = cache.cachedURL(for: media)

        XCTAssertNotNil(found)
        XCTAssertEqual(try Data(contentsOf: found!), bytes)
    }

    func testBlobKeepsItsExtension() throws {
        // load-bearing: AVPlayerItem and PDFView sniff type partly from the path, and an extensionless
        // blob fails with an error that looks like a corrupt download
        let bytes = Data("x".utf8)
        let url = try store(file(id: 7, bytes: bytes, mime: "application/pdf", kind: .sheet), bytes: bytes)

        XCTAssertEqual(url.pathExtension, "pdf")
    }

    func testContentAddressingStoresSharedBytesOnce() throws {
        // the same backing track attached to two songs, or re-uploaded under a new id
        let bytes = Data("shared".utf8)
        let first = file(id: 1, bytes: bytes)
        let second = file(id: 2, bytes: bytes)
        _ = try store(first, bytes: bytes)

        // the second file needs no transfer at all, because the bytes are already here
        XCTAssertNotNil(cache.cachedURL(for: second))
        XCTAssertEqual(cache.usedBytes, Int64(bytes.count), "the same bytes must not be stored twice")
    }

    func testAdoptRejectsBytesThatDoNotMatchTheDigest() throws {
        let declared = file(id: 7, bytes: Data("expected".utf8))
        let temp = root.appendingPathComponent("incoming")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("tampered".utf8).write(to: temp)

        XCTAssertThrowsError(try cache.adopt(temp, for: declared)) { error in
            XCTAssertTrue(error is MediaCacheError)
        }
        XCTAssertNil(cache.cachedURL(for: declared))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path), "the rejected file should be gone")
    }

    func testAFileWithNoDigestIsNotCacheable() throws {
        // unverifiable, so it can never be content-addressed
        let bytes = Data("x".utf8)
        var media = file(id: 7, bytes: bytes)
        media = MediaFile(
            id: media.id, bandId: media.bandId, songId: nil, name: media.name, kind: media.kind,
            mimeType: media.mimeType, sizeBytes: media.sizeBytes, sha256: nil, ownerBandMemberId: nil,
            uploadState: .ready, takedownState: .active, uploadedByUserId: 1, uploadedAt: nil,
            createdAt: "", deletedAt: nil, downloadable: true
        )

        XCTAssertNil(cache.cachedURL(for: media))
    }

    func testMetadataSurvivesReopening() throws {
        let bytes = Data("hello".utf8)
        _ = try store(file(id: 7, bytes: bytes), bytes: bytes)

        let reopened = MediaCache(root: root, budgetBytes: 1000, now: { self.clock })

        XCTAssertEqual(reopened.entries().count, 1)
        XCTAssertEqual(reopened.entries().first?.name, "Track 7")
    }

    func testACorruptManifestCostsMetadataButNotBytes() throws {
        let bytes = Data("hello".utf8)
        let media = file(id: 7, bytes: bytes)
        _ = try store(media, bytes: bytes)
        try Data("{{{ not json".utf8).write(to: cache.manifestURL)

        let reopened = MediaCache(root: root, budgetBytes: 1000, now: { self.clock })

        // the digest is in the filename, so the bytes stay usable offline; only the label is lost
        XCTAssertNotNil(reopened.cachedURL(for: media))
    }

    func testReconcileDropsEntriesWhoseBlobVanished() throws {
        let bytes = Data("hello".utf8)
        let media = file(id: 7, bytes: bytes)
        let url = try store(media, bytes: bytes)
        try FileManager.default.removeItem(at: url) // manual deletion, or a restore-from-backup

        cache.reconcile()

        XCTAssertTrue(cache.entries().isEmpty)
        XCTAssertEqual(cache.usedBytes, 0)
    }

    func testEvictionRemovesTheLeastRecentlyUsedFirst() throws {
        let a = Data(repeating: 1, count: 400)
        let b = Data(repeating: 2, count: 400)
        _ = try store(file(id: 1, bytes: a), bytes: a)
        _ = try store(file(id: 2, bytes: b), bytes: b)
        tick()
        cache.touch(fileId: 1) // 2 is now the oldest

        try cache.makeRoom(forIncoming: 400)

        XCTAssertEqual(cache.entries().map(\.fileId), [1])
    }

    func testPinnedFilesSurviveEvictionEvenWhenOldest() throws {
        // pinned exists from day one so offline pinning later needs no migration
        let a = Data(repeating: 1, count: 400)
        let b = Data(repeating: 2, count: 400)
        _ = try store(file(id: 1, bytes: a), bytes: a)
        _ = try store(file(id: 2, bytes: b), bytes: b)
        cache.setPinned(fileId: 1, pinned: true)
        tick()
        cache.touch(fileId: 2) // 1 is the LRU, but pinned

        try cache.makeRoom(forIncoming: 400)

        XCTAssertEqual(cache.entries().map(\.fileId), [1], "the pinned file must be the survivor")
    }

    func testAFileLargerThanTheBudgetStillProceeds() throws {
        // refusing a download the user explicitly asked for is worse than exceeding a self-imposed limit
        let a = Data(repeating: 1, count: 400)
        _ = try store(file(id: 1, bytes: a), bytes: a)

        try cache.makeRoom(forIncoming: 5000)

        XCTAssertTrue(cache.entries().isEmpty)
    }

    func testRemovingAFileDeletesItsBytes() throws {
        let bytes = Data("hello".utf8)
        let media = file(id: 7, bytes: bytes)
        _ = try store(media, bytes: bytes)

        cache.remove(fileId: 7)

        XCTAssertNil(cache.cachedURL(for: media))
        XCTAssertEqual(cache.usedBytes, 0)
    }

    func testRetainOnlyIgnoresAnEmptyServerList() throws {
        // guards a nasty interaction: reading "no files" as "everything is gone" would let a backend
        // outage wipe a member's offline library at the worst possible moment
        let bytes = Data("hello".utf8)
        let media = file(id: 7, bytes: bytes)
        _ = try store(media, bytes: bytes)

        cache.retainOnly(serverFileIds: [])

        XCTAssertNotNil(cache.cachedURL(for: media))
    }

    func testRetainOnlyDropsFilesDeletedElsewhere() throws {
        let a = Data("a".utf8)
        let b = Data("b".utf8)
        _ = try store(file(id: 1, bytes: a), bytes: a)
        _ = try store(file(id: 2, bytes: b), bytes: b)

        cache.retainOnly(serverFileIds: [1])

        XCTAssertEqual(cache.entries().map(\.fileId), [1])
    }

    func testExtensionsAreDerivedFromTheMimeType() {
        XCTAssertEqual(MediaCache.fileExtension(forMime: "audio/mpeg"), "mp3")
        XCTAssertEqual(MediaCache.fileExtension(forMime: "application/pdf"), "pdf")
        XCTAssertEqual(MediaCache.fileExtension(forMime: "image/jpeg"), "jpg")
        XCTAssertEqual(MediaCache.fileExtension(forMime: "video/mp4"), "mp4")
        // parameters and case must not change the answer
        XCTAssertEqual(MediaCache.fileExtension(forMime: "Audio/MPEG; charset=binary"), "mp3")
        XCTAssertEqual(MediaCache.fileExtension(forMime: "application/x-unknown"), "")
    }
}
