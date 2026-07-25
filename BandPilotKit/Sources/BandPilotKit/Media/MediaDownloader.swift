import Foundation

/// Moving bytes to and from the band's bucket, behind a protocol so the downloader is testable without
/// a network and so a background `URLSession` can be swapped in later without touching callers.
public protocol FileTransferring: Sendable {
    /// - Parameter offset: reserved for resumable downloads. Present in the signature from the start so
    ///   adding resume later is an implementation change rather than an API change.
    func download(
        _ envelope: TransferEnvelope,
        offset: Int64,
        progress: @Sendable @escaping (Int64, Int64) -> Void
    ) async throws -> URL

    /// - Returns: the provider's ETag, when it reported one.
    func upload(
        _ envelope: TransferEnvelope,
        fromFile: URL,
        progress: @Sendable @escaping (Int64, Int64) -> Void
    ) async throws -> String?
}

/// Where a transfer envelope comes from. `APIClient` conforms, and tests inject a fake.
public protocol MediaEnvelopeProviding: Sendable {
    func downloadEnvelope(bandId: Int, fileId: Int) async throws -> TransferEnvelope
}

public enum MediaTransferError: Error, Sendable, Equatable {
    /// the presigned URL expired, and a refetch did not help either
    case linkExpired
    /// the object is gone from the bucket — an admin deleted it, or a lifecycle rule removed it
    case gone
    case providerUnavailable(status: Int)
    case integrityFailed
    case notEnoughSpace(needBytes: Int64)

    /// Wording for the UI. Deliberately never says "the backend is waking up": the failing host here is
    /// the band's storage provider, and blaming the Roadie backend for a Cloudflare problem sends people
    /// to wait for something that will not help.
    public var userMessage: String {
        switch self {
        case .linkExpired: return "This file's link expired — please try again."
        case .gone: return "This file is no longer available in your band's storage."
        case .providerUnavailable: return "Your band's storage is not responding — please try again later."
        case .integrityFailed: return "Download damaged — please try again."
        case .notEnoughSpace(let need): return "Not enough free space (needs \(need / 1_048_576) MB)."
        }
    }
}

/// Downloads one media file into the cache, verifying it before it becomes visible.
///
/// An actor, because the in-flight table must not be raced: two rows referencing the same file (or two
/// taps) have to share one transfer rather than competing.
public actor MediaDownloader {

    private let cache: MediaCache
    private let transfer: any FileTransferring
    private let envelopes: any MediaEnvelopeProviding
    private let freeSpaceBytes: @Sendable () -> Int64

    private var inFlight: [Int: Task<URL, Error>] = [:]
    /// Envelopes are reused for their whole validity window rather than refetched per file, because
    /// refetching means a round trip to an instance that sleeps after 15 minutes.
    private var memoizedEnvelopes: [Int: TransferEnvelope] = [:]

    public init(
        cache: MediaCache,
        transfer: any FileTransferring,
        envelopes: any MediaEnvelopeProviding,
        freeSpaceBytes: @escaping @Sendable () -> Int64 = { MediaDownloader.volumeFreeBytes() }
    ) {
        self.cache = cache
        self.transfer = transfer
        self.envelopes = envelopes
        self.freeSpaceBytes = freeSpaceBytes
    }

    /// - Returns: the cached file URL. A cache hit answers before anything else, including the envelope
    ///   call — which is what lets a cached file open instantly while the backend is asleep.
    public func ensureCached(
        bandId: Int,
        file: MediaFile,
        progress: @Sendable @escaping (Int64, Int64) -> Void = { _, _ in }
    ) async throws -> URL {
        if let hit = cache.cachedURL(for: file) {
            cache.touch(fileId: file.id)
            return hit
        }
        guard file.sha256 != nil else { throw MediaCacheError.notVerifiable }

        if let existing = inFlight[file.id] {
            return try await existing.value
        }

        let task = Task<URL, Error> { [self] in
            try await performTransfer(bandId: bandId, file: file, progress: progress)
        }
        inFlight[file.id] = task
        defer { inFlight[file.id] = nil }
        return try await task.value
    }

    /// Explicit user cancellation only. A view disappearing must *not* cancel: SwiftUI cancels a `.task`
    /// when its view scrolls away, and a download dying because the user scrolled would be baffling.
    public func cancel(fileId: Int) {
        inFlight[fileId]?.cancel()
        inFlight[fileId] = nil
    }

    private func performTransfer(
        bandId: Int,
        file: MediaFile,
        progress: @Sendable @escaping (Int64, Int64) -> Void
    ) async throws -> URL {
        guard freeSpaceBytes() > file.sizeBytes else {
            throw MediaTransferError.notEnoughSpace(needBytes: file.sizeBytes)
        }
        try cache.makeRoom(forIncoming: file.sizeBytes)

        var envelope = try await usableEnvelope(bandId: bandId, fileId: file.id)
        var refetched = false

        while true {
            do {
                let temporary = try await transfer.download(envelope, offset: 0, progress: progress)
                do {
                    return try cache.adopt(temporary, for: file)
                } catch MediaCacheError.integrityFailed {
                    throw MediaTransferError.integrityFailed
                }
            } catch MediaTransferError.linkExpired where !refetched {
                // the common real case: a presigned URL that expired between minting and use
                memoizedEnvelopes[file.id] = nil
                envelope = try await usableEnvelope(bandId: bandId, fileId: file.id)
                refetched = true
            }
        }
    }

    private func usableEnvelope(bandId: Int, fileId: Int) async throws -> TransferEnvelope {
        if let memoized = memoizedEnvelopes[fileId], memoized.isUsable() { return memoized }
        let fresh = try await envelopes.downloadEnvelope(bandId: bandId, fileId: fileId)
        memoizedEnvelopes[fileId] = fresh
        return fresh
    }

    /// Free space on the volume holding the cache, so a transfer that cannot finish fails before it
    /// starts rather than dying mid-stream with an opaque IO error.
    public static func volumeFreeBytes() -> Int64 {
        guard let root = try? MediaCache.defaultRoot(),
              let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage
        else { return .max }
        return Int64(available)
    }
}
