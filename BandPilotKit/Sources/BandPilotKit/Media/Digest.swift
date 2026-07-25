import CryptoKit
import Foundation

/// Hashing, for cache keys and upload integrity.
///
/// `CryptoKit` is a system framework, not a package dependency, so this keeps BandPilotKit's
/// zero-dependency rule intact.
public enum Digest {

    /// Streamed SHA-256 of a file, as lowercase hex.
    ///
    /// Read in chunks rather than loading the file: a 200 MB video would otherwise be held in memory
    /// twice over. Hashed in one pass *after* a download completes rather than incrementally while
    /// writing, because `SHA256`'s state cannot be restored — so an incremental digest silently becomes
    /// wrong the moment a transfer resumes from a partial file.
    public static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: chunkBytes), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Base64 MD5, for the `Content-MD5` the backend signs into an upload so the **provider** verifies
    /// the bytes. Weak by design and not used for anything security-bearing — content identity is
    /// SHA-256 above.
    public static func md5Base64(of data: Data) -> String {
        Data(Insecure.MD5.hash(data: data)).base64EncodedString()
    }

    private static let chunkBytes = 1024 * 1024
}
