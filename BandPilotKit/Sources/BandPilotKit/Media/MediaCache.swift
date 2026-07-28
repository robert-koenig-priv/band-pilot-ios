import Foundation

public enum MediaCacheError: Error, Sendable {
    /// the bytes that arrived do not hash to the digest the backend recorded
    case integrityFailed
    /// the file carries no digest, so it can never be content-addressed
    case notVerifiable
}

/// Metadata the offline UI needs and the filesystem cannot express. All of it re-fetchable, so losing
/// it is cosmetic — unlike the bytes.
public struct MediaCacheEntry: Codable, Sendable, Hashable {
    public let fileId: Int
    public let digest: String
    public let fileExtension: String
    public let name: String
    public let kind: MediaFileKind
    public let mimeType: String
    public let bytes: Int64
    public let songId: Int?
    public let ownerBandMemberId: Int?
    public let cachedAt: Date
    public var lastAccessedAt: Date
    /// Reserved for the later offline mode. Always false in this version, but present from day one so
    /// pinning needs no migration — and already honoured by eviction.
    public var pinned: Bool
}

/// On-disk media cache.
///
/// ## Location: Application Support, not Caches
///
/// `Caches` is purgeable by the OS at any moment under disk pressure, with no notification. That is
/// fatal for the point of this cache: "I pinned tonight's setlist" cannot mean "unless iOS reclaimed
/// space on the train". The cost of that choice is that the budget is ours to enforce, hence
/// ``makeRoom(forIncoming:)``. The directory is excluded from iCloud backup, because a member with 2 GB
/// of band audio should not have it counted against their backup quota.
///
/// ## Content addressing
///
/// Blobs are named by their own SHA-256, so verification is simply "does this file hash to its own
/// name", and the same bytes attached to two songs are stored once. A truncated or corrupt manifest can
/// therefore only lose *metadata* — the digests survive in the filenames — and can never produce a
/// wrong-bytes bug.
///
/// The extension is appended deliberately: `AVURLAsset` and `PDFView` sniff type partly from the path,
/// and an extensionless blob fails with an error that reads as a corrupt download.
///
/// Not an actor: every operation is synchronous filesystem work, and making it an actor would force
/// `await` into SwiftUI accessors that need to answer during layout.
public final class MediaCache: @unchecked Sendable {

    private let root: URL
    private let budgetBytes: Int64
    private let now: @Sendable () -> Date
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private var index: [Int: MediaCacheEntry] = [:]

    /// - Parameters:
    ///   - root: injected so tests can point at a temp directory; production uses
    ///     ``defaultRoot()``.
    ///   - now: injected because two files cached in the same instant have no defined LRU order.
    public init(root: URL, budgetBytes: Int64, now: @escaping @Sendable () -> Date = { Date() }) {
        self.root = root
        self.budgetBytes = budgetBytes
        self.now = now
        try? fileManager.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)
        excludeFromBackup()
        load()
        reconcile()
    }

    /// `Library/Application Support/BandPilot/Media` — durable, and not `Caches`.
    public static func defaultRoot() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("BandPilot/Media", isDirectory: true)
    }

    // MARK: - Layout

    private var blobsDirectory: URL { root.appendingPathComponent("blobs", isDirectory: true) }

    var manifestURL: URL { root.appendingPathComponent("index.json") }

    private func blobURL(digest: String, fileExtension: String) -> URL {
        // a two-character shard keeps any one directory from growing unbounded
        let shard = String(digest.prefix(2))
        let name = fileExtension.isEmpty ? digest : "\(digest).\(fileExtension)"
        return blobsDirectory.appendingPathComponent(shard, isDirectory: true).appendingPathComponent(name)
    }

    // MARK: - Reads

    /// - Returns: the cached file, or nil when absent or when the file carries no digest.
    public func cachedURL(for file: MediaFile) -> URL? {
        guard let digest = file.sha256 else { return nil }
        let url = blobURL(digest: digest, fileExtension: Self.fileExtension(forMime: file.mimeType))
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    public func entries() -> [MediaCacheEntry] {
        lock.withLock { Array(self.index.values) }.sorted { $0.lastAccessedAt < $1.lastAccessedAt }
    }

    /// Measured from the filesystem, since the manifest is only a claim.
    public var usedBytes: Int64 {
        guard let walker = fileManager.enumerator(at: blobsDirectory, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    // MARK: - Writes

    /// Verify a finished download and move it in.
    ///
    /// - Throws: ``MediaCacheError/integrityFailed`` when the bytes disagree with the recorded digest —
    ///   the temporary file is deleted in that case, so corrupt bytes can neither linger nor be served.
    @discardableResult
    public func adopt(_ temporary: URL, for file: MediaFile) throws -> URL {
        guard let digest = file.sha256 else {
            try? fileManager.removeItem(at: temporary)
            throw MediaCacheError.notVerifiable
        }
        guard try Digest.sha256Hex(ofFileAt: temporary) == digest else {
            try? fileManager.removeItem(at: temporary)
            throw MediaCacheError.integrityFailed
        }

        let ext = Self.fileExtension(forMime: file.mimeType)
        let target = blobURL(digest: digest, fileExtension: ext)
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: target.path) {
            // same bytes already here (two songs sharing a backing track); keep the existing blob
            try? fileManager.removeItem(at: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: target)
        }

        let stamp = now()
        lock.withLock {
            index[file.id] = MediaCacheEntry(
                fileId: file.id, digest: digest, fileExtension: ext, name: file.name, kind: file.kind,
                mimeType: file.mimeType, bytes: file.sizeBytes, songId: file.songId,
                ownerBandMemberId: file.ownerBandMemberId, cachedAt: stamp, lastAccessedAt: stamp,
                pinned: false
            )
        }
        flush()
        return target
    }

    public func touch(fileId: Int) {
        lock.withLock { index[fileId]?.lastAccessedAt = now() }
        flush()
    }

    public func setPinned(fileId: Int, pinned: Bool) {
        lock.withLock { index[fileId]?.pinned = pinned }
        flush()
    }

    public func remove(fileId: Int) {
        let entry = lock.withLock { index.removeValue(forKey: fileId) }
        if let entry {
            // only delete the blob when no other entry shares those bytes
            let shared = lock.withLock { index.values.contains { $0.digest == entry.digest } }
            if !shared {
                try? fileManager.removeItem(at: blobURL(digest: entry.digest, fileExtension: entry.fileExtension))
            }
        }
        flush()
    }

    /// Drop anything the server no longer lists — a file deleted on another device.
    ///
    /// An empty set is deliberately ignored: reading "no files" as "everything is gone" would let a
    /// backend outage wipe a member's offline library at the worst possible moment.
    public func retainOnly(serverFileIds: Set<Int>) {
        guard !serverFileIds.isEmpty else { return }
        let stale = lock.withLock { index.keys.filter { !serverFileIds.contains($0) } }
        stale.forEach { remove(fileId: $0) }
    }

    /// Evict least-recently-used blobs until `incoming` fits.
    ///
    /// Pinned entries are never evicted. If the incoming file exceeds the whole budget we evict
    /// everything evictable and proceed anyway: refusing a download the user explicitly asked for is
    /// worse than briefly exceeding a self-imposed limit.
    public func makeRoom(forIncoming incoming: Int64) throws {
        var used = usedBytes
        guard used + incoming > budgetBytes else { return }
        // fileId breaks ties, so two blobs stamped in the same instant still evict predictably
        let victims = entries()
            .filter { !$0.pinned }
            .sorted { ($0.lastAccessedAt, $0.fileId) < ($1.lastAccessedAt, $1.fileId) }
        for victim in victims {
            if used + incoming <= budgetBytes { return }
            used -= victim.bytes
            remove(fileId: victim.fileId)
        }
    }

    /// Self-heal: drop entries whose blob is gone (manual deletion, restore-from-backup, our own crash).
    public func reconcile() {
        let missing = lock.withLock {
            index.values
                .filter { !fileManager.fileExists(atPath: blobURL(digest: $0.digest, fileExtension: $0.fileExtension).path) }
                .map(\.fileId)
        }
        guard !missing.isEmpty else { return }
        lock.withLock { missing.forEach { index.removeValue(forKey: $0) } }
        flush()
    }

    // MARK: - Manifest

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL) else { return }
        // A corrupt manifest is recoverable: digests survive in the filenames and everything else comes
        // back on the next successful list. Losing it must never mean losing the bytes.
        guard let decoded = try? JSONDecoder().decode([MediaCacheEntry].self, from: data) else { return }
        lock.withLock { index = Dictionary(uniqueKeysWithValues: decoded.map { ($0.fileId, $0) }) }
    }

    /// Atomic, so an interrupted write cannot leave a half-written manifest.
    private func flush() {
        let snapshot = lock.withLock { Array(index.values) }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    private func excludeFromBackup() {
        var url = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    // MARK: - Mime types

    /// The extension is not cosmetic — see the type docs.
    public static func fileExtension(forMime mime: String) -> String {
        let key = mime.lowercased().split(separator: ";").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return extensions[key] ?? ""
    }

    private static let extensions: [String: String] = [
        "audio/mpeg": "mp3", "audio/mp4": "m4a", "audio/aac": "aac", "audio/ogg": "ogg",
        "audio/wav": "wav", "audio/x-wav": "wav", "audio/flac": "flac",
        "video/mp4": "mp4", "video/quicktime": "mov", "video/webm": "webm",
        "application/pdf": "pdf",
        "image/jpeg": "jpg", "image/png": "png", "image/heic": "heic",
        "image/webp": "webp", "image/gif": "gif",
    ]
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
