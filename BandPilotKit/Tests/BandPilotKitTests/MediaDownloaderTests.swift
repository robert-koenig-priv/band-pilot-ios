import XCTest
@testable import BandPilotKit

/// Fake byte transfer: scripted outcomes, no network.
private actor FakeTransfer: FileTransferring {
    enum Outcome: Sendable {
        case bytes(Data)
        case failure(MediaTransferError)
    }

    private var outcomes: [Outcome]
    private(set) var downloadCount = 0

    init(_ outcomes: [Outcome]) { self.outcomes = outcomes }

    func download(
        _ envelope: TransferEnvelope,
        offset: Int64,
        progress: @Sendable @escaping (Int64, Int64) -> Void
    ) async throws -> URL {
        downloadCount += 1
        let outcome = outcomes.isEmpty ? Outcome.failure(.gone) : outcomes.removeFirst()
        switch outcome {
        case .failure(let error):
            throw error
        case .bytes(let data):
            progress(Int64(data.count), Int64(data.count))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID().uuidString)")
            try data.write(to: url)
            return url
        }
    }

    func upload(
        _ envelope: TransferEnvelope,
        fromFile: URL,
        progress: @Sendable @escaping (Int64, Int64) -> Void
    ) async throws -> String? { nil }
}

private actor FakeEnvelopes: MediaEnvelopeProviding {
    private(set) var calls = 0
    private let expiresAt: String

    init(expiresAt: String = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))) {
        self.expiresAt = expiresAt
    }

    func downloadEnvelope(bandId: Int, fileId: Int) async throws -> TransferEnvelope {
        calls += 1
        return TransferEnvelope(
            method: "GET", url: URL(string: "https://bucket.example/o")!, expiresAt: expiresAt
        )
    }
}

final class MediaDownloaderTests: XCTestCase {

    private var root: URL!
    private var cache: MediaCache!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dl-\(UUID().uuidString)")
        cache = MediaCache(root: root, budgetBytes: 10_000)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func file(_ bytes: Data, id: Int = 7, digest: String? = nil) -> MediaFile {
        MediaFile(
            id: id, bandId: 1, bandSongId: nil, name: "Track", kind: .audio, mimeType: "audio/mpeg",
            sizeBytes: Int64(bytes.count), sha256: digest ?? Digest.sha256Hex(of: bytes),
            ownerBandMemberId: nil, uploadState: .ready, takedownState: .active, uploadedByUserId: 1,
            uploadedAt: nil, createdAt: "", deletedAt: nil, downloadable: true
        )
    }

    private func downloader(
        _ transfer: FakeTransfer,
        _ envelopes: FakeEnvelopes = FakeEnvelopes(),
        freeSpace: Int64 = .max
    ) -> MediaDownloader {
        MediaDownloader(cache: cache, transfer: transfer, envelopes: envelopes, freeSpaceBytes: { freeSpace })
    }

    func testASuccessfulDownloadIsCachedAndVerified() async throws {
        let bytes = Data("the bytes".utf8)
        let media = file(bytes)
        let url = try await downloader(FakeTransfer([.bytes(bytes)]))
            .ensureCached(bandId: 1, file: media)

        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertNotNil(cache.cachedURL(for: media))
    }

    func testACacheHitCostsNoRequestAtAll() async throws {
        let bytes = Data("cached".utf8)
        let media = file(bytes)
        let transfer = FakeTransfer([.bytes(bytes)])
        let envelopes = FakeEnvelopes()
        let sut = downloader(transfer, envelopes)
        _ = try await sut.ensureCached(bandId: 1, file: media)

        _ = try await sut.ensureCached(bandId: 1, file: media)

        // this is what makes a cached file open instantly while the backend is asleep
        let downloads = await transfer.downloadCount
        let envelopeCalls = await envelopes.calls
        XCTAssertEqual(downloads, 1)
        XCTAssertEqual(envelopeCalls, 1, "a cache hit must not even fetch an envelope")
    }

    func testBytesThatDoNotMatchTheDigestAreRejected() async throws {
        let declared = file(Data("expected".utf8))
        let sut = downloader(FakeTransfer([.bytes(Data("something else".utf8))]))

        do {
            _ = try await sut.ensureCached(bandId: 1, file: declared)
            XCTFail("expected an integrity failure")
        } catch {
            XCTAssertEqual(error as? MediaTransferError, .integrityFailed)
        }
        XCTAssertNil(cache.cachedURL(for: declared), "corrupt bytes must not be cached")
    }

    func testTwoConcurrentRequestsShareOneDownload() async throws {
        let bytes = Data("shared".utf8)
        let media = file(bytes)
        let transfer = FakeTransfer([.bytes(bytes), .bytes(bytes)])
        let sut = downloader(transfer)

        async let first = sut.ensureCached(bandId: 1, file: media)
        async let second = sut.ensureCached(bandId: 1, file: media)
        _ = try await (first, second)

        // two rows referencing the same file must not double-fetch it
        let downloads = await transfer.downloadCount
        XCTAssertEqual(downloads, 1)
    }

    func testAnExpiredLinkIsRefetchedOnceThenSucceeds() async throws {
        let bytes = Data("retry".utf8)
        let transfer = FakeTransfer([.failure(.linkExpired), .bytes(bytes)])
        let envelopes = FakeEnvelopes()

        _ = try await downloader(transfer, envelopes).ensureCached(bandId: 1, file: file(bytes))

        let envelopeCalls = await envelopes.calls
        XCTAssertEqual(envelopeCalls, 2, "the envelope should have been refetched exactly once")
    }

    func testAPersistentlyExpiredLinkGivesUp() async throws {
        let bytes = Data("nope".utf8)
        let transfer = FakeTransfer([.failure(.linkExpired), .failure(.linkExpired)])
        let envelopes = FakeEnvelopes()
        let sut = downloader(transfer, envelopes)

        do {
            _ = try await sut.ensureCached(bandId: 1, file: file(bytes))
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? MediaTransferError, .linkExpired)
        }
        let envelopeCalls = await envelopes.calls
        XCTAssertLessThanOrEqual(envelopeCalls, 2, "must not retry indefinitely")
    }

    func testAMissingObjectIsNotRetried() async throws {
        let bytes = Data("gone".utf8)
        let transfer = FakeTransfer([.failure(.gone)])
        let sut = downloader(transfer)

        do {
            _ = try await sut.ensureCached(bandId: 1, file: file(bytes))
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? MediaTransferError, .gone)
        }
        let downloads = await transfer.downloadCount
        XCTAssertEqual(downloads, 1, "404 is terminal")
    }

    func testInsufficientSpaceFailsBeforeAnyTransfer() async throws {
        let bytes = Data(repeating: 0, count: 5000)
        let transfer = FakeTransfer([.bytes(bytes)])
        let sut = downloader(transfer, freeSpace: 10)

        do {
            _ = try await sut.ensureCached(bandId: 1, file: file(bytes))
            XCTFail("expected a space failure")
        } catch {
            XCTAssertEqual(error as? MediaTransferError, .notEnoughSpace(needBytes: 5000))
        }
        let downloads = await transfer.downloadCount
        XCTAssertEqual(downloads, 0, "must not start a transfer it cannot finish")
    }

    func testAFileWithoutADigestIsRefused() async throws {
        let bytes = Data("x".utf8)
        let transfer = FakeTransfer([.bytes(bytes)])
        var media = file(bytes)
        media = MediaFile(
            id: media.id, bandId: 1, bandSongId: nil, name: media.name, kind: media.kind,
            mimeType: media.mimeType, sizeBytes: media.sizeBytes, sha256: nil, ownerBandMemberId: nil,
            uploadState: .ready, takedownState: .active, uploadedByUserId: 1, uploadedAt: nil,
            createdAt: "", deletedAt: nil, downloadable: true
        )

        do {
            _ = try await downloader(transfer).ensureCached(bandId: 1, file: media)
            XCTFail("expected a refusal")
        } catch {
            XCTAssertTrue(error is MediaCacheError)
        }
        let downloads = await transfer.downloadCount
        XCTAssertEqual(downloads, 0)
    }

    func testProgressReachesTheFullSize() async throws {
        let bytes = Data(repeating: 7, count: 4096)
        let seen = Reported()
        _ = try await downloader(FakeTransfer([.bytes(bytes)]))
            .ensureCached(bandId: 1, file: file(bytes)) { done, _ in Task { await seen.add(done) } }

        // give the detached reporting tasks a moment to land
        try await Task.sleep(nanoseconds: 50_000_000)
        let lastReported = await seen.last
        XCTAssertEqual(lastReported, Int64(bytes.count))
    }

    func testAnExpiredEnvelopeIsNotReused() async throws {
        // a stale envelope must be discarded rather than sent and rejected
        let past = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))
        let envelope = TransferEnvelope(
            method: "GET", url: URL(string: "https://x")!, expiresAt: past
        )
        XCTAssertFalse(envelope.isUsable())
    }
}

private actor Reported {
    private var values: [Int64] = []
    func add(_ value: Int64) { values.append(value) }
    var last: Int64? { values.last }
}
