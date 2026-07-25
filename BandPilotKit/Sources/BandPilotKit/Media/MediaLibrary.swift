import Foundation

/// What the UI shows for one file.
public enum MediaFileState: Sendable, Equatable {
    case absent
    case transferring(fraction: Double, done: Int64, total: Int64)
    case cached(URL)
    case failed(String)
    /// the object is gone from the bucket; retrying cannot help
    case unavailable
}

/// The app-facing façade over ``MediaDownloader`` and ``MediaCache``.
///
/// `@MainActor @Observable`, matching how `SessionStore` and the view models already publish state, so
/// SwiftUI can read `state(for:)` during layout without `await`.
///
/// One instance per app, threaded down by init parameter the way `api` and `session` already are, rather
/// than through `@Environment` — this codebase passes dependencies explicitly.
@MainActor
@Observable
public final class MediaLibrary {

    private let cache: MediaCache
    private let downloader: MediaDownloader

    public private(set) var states: [Int: MediaFileState] = [:]

    public init(cache: MediaCache, downloader: MediaDownloader) {
        self.cache = cache
        self.downloader = downloader
    }

    /// Convenience wiring for the app: real cache, real transfer, `APIClient` as the envelope source.
    ///
    /// Non-throwing on purpose. If Application Support is somehow unavailable it falls back to a
    /// temporary directory, where downloads simply will not survive — which is much better than
    /// refusing to launch the app over a cache location.
    public static func live(api: APIClient) -> MediaLibrary {
        let root = (try? MediaCache.defaultRoot())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("BandPilotMedia", isDirectory: true)
        let cache = MediaCache(root: root, budgetBytes: defaultBudgetBytes)
        return MediaLibrary(
            cache: cache,
            downloader: MediaDownloader(cache: cache, transfer: URLSessionFileTransfer(), envelopes: api)
        )
    }

    /// 2 GB. Enough for a band's practice material, small enough that the app never quietly becomes the
    /// largest thing on a phone — and the storage screen makes the footprint visible either way.
    public static let defaultBudgetBytes: Int64 = 2 * 1024 * 1024 * 1024

    /// The state to render.
    ///
    /// Consults the cache rather than only the state map, so a file downloaded in an earlier session
    /// reads as ``MediaFileState/cached(_:)`` with no network call at all. That is what makes the panel
    /// work offline and while the backend is asleep.
    public func state(for file: MediaFile) -> MediaFileState {
        if let known = states[file.id], known != .absent { return known }
        if let url = cache.cachedURL(for: file) { return .cached(url) }
        return .absent
    }

    public func isCached(_ file: MediaFile) -> Bool { cache.cachedURL(for: file) != nil }

    /// Download if needed, then return the local file.
    ///
    /// - Returns: nil on failure; the reason is left in ``states`` for the row to render, because a view
    ///   needs to show the cause rather than have an error thrown past it.
    @discardableResult
    public func ensureCached(bandId: Int, file: MediaFile) async -> URL? {
        if let url = cache.cachedURL(for: file) {
            cache.touch(fileId: file.id)
            states[file.id] = .cached(url)
            return url
        }
        states[file.id] = .transferring(fraction: 0, done: 0, total: file.sizeBytes)
        do {
            let url = try await downloader.ensureCached(bandId: bandId, file: file) { [weak self] done, total in
                Task { @MainActor [weak self] in
                    self?.states[file.id] = .transferring(
                        fraction: total > 0 ? Double(done) / Double(total) : 0, done: done, total: total
                    )
                }
            }
            states[file.id] = .cached(url)
            return url
        } catch let error as MediaTransferError {
            // "gone" is terminal, so it reads differently from something worth retrying
            states[file.id] = error == .gone ? .unavailable : .failed(error.userMessage)
            return nil
        } catch is MediaCacheError {
            states[file.id] = .failed(MediaTransferError.integrityFailed.userMessage)
            return nil
        } catch {
            states[file.id] = .failed("Download failed — check your connection.")
            return nil
        }
    }

    /// Explicit user cancellation. The partial download is discarded, not resumed — see
    /// ``MediaDownloader``.
    public func cancel(_ file: MediaFile) async {
        await downloader.cancel(fileId: file.id)
        states[file.id] = .absent
    }

    /// Clear a failure so the row offers a retry rather than staying stuck on the message.
    public func clearFailure(_ file: MediaFile) {
        if case .failed = states[file.id] { states[file.id] = .absent }
    }

    public func removeDownload(_ file: MediaFile) {
        cache.remove(fileId: file.id)
        states[file.id] = .absent
    }

    /// Adopt a file the user just uploaded, so the uploader never downloads back what they just sent.
    public func adoptUploaded(_ file: MediaFile, from temporary: URL) {
        if let url = try? cache.adopt(temporary, for: file) {
            states[file.id] = .cached(url)
        }
    }

    /// Reconcile with a **successful** server list.
    ///
    /// ``MediaCache/retainOnly(serverFileIds:)`` ignores an empty set on purpose, so a backend outage
    /// cannot wipe a member's offline library — never call this with the result of a failed load.
    public func reconcile(with files: [MediaFile]) {
        cache.retainOnly(serverFileIds: Set(files.map(\.id)))
        for file in files where cache.cachedURL(for: file) == nil {
            if case .cached = states[file.id] { states[file.id] = .absent }
        }
    }

    public var usedBytes: Int64 { cache.usedBytes }
    public var budgetBytes: Int64 { Self.defaultBudgetBytes }

    /// Drop every download — the storage screen's "remove downloads".
    public func removeAllDownloads() {
        for entry in cache.entries() { cache.remove(fileId: entry.fileId) }
        states.removeAll()
    }
}

/// `APIClient` is the real envelope source; the protocol exists so tests need no network.
extension APIClient: MediaEnvelopeProviding {
    public func downloadEnvelope(bandId: Int, fileId: Int) async throws -> TransferEnvelope {
        try await send(.mediaDownloadURL(bandId: bandId, fileId: fileId))
    }
}
