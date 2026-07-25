import Foundation

/// `URLSession`-backed byte transfer.
///
/// Uses `URLSessionDownloadTask`/`uploadTask` with a per-task delegate rather than
/// `URLSession.bytes(for:)`. `AsyncBytes` iterates one `UInt8` at a time through the async-sequence
/// machinery, which for a 200 MB file is dramatically slower than it looks — it reads like the modern
/// choice and is a performance trap.
///
/// Nothing here branches on the storage provider: it applies the envelope's method, URL and headers
/// verbatim, so a future provider needing an `Authorization` header requires no change.
public final class URLSessionFileTransfer: NSObject, FileTransferring, @unchecked Sendable {

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
        super.init()
    }

    public func download(
        _ envelope: TransferEnvelope,
        offset: Int64,
        progress: @Sendable @escaping (Int64, Int64) -> Void
    ) async throws -> URL {
        var request = URLRequest(url: envelope.url)
        request.httpMethod = envelope.method
        // verbatim, because they are part of the signature
        for (name, value) in envelope.headers { request.setValue(value, forHTTPHeaderField: name) }
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }

        let observer = ProgressObserver(progress: progress)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.downloadTask(with: request) { url, response, error in
                    if let error { return continuation.resume(throwing: error) }
                    guard let url, let http = response as? HTTPURLResponse else {
                        return continuation.resume(throwing: MediaTransferError.providerUnavailable(status: 0))
                    }
                    if let failure = Self.failure(for: http.statusCode) {
                        return continuation.resume(throwing: failure)
                    }
                    // the downloaded file is deleted as soon as this closure returns, so move it now
                    let staged = FileManager.default.temporaryDirectory
                        .appendingPathComponent("bp-\(UUID().uuidString)")
                    do {
                        try FileManager.default.moveItem(at: url, to: staged)
                        continuation.resume(returning: staged)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                task.delegate = observer
                observer.task = task
                task.resume()
            }
        } onCancel: {
            observer.task?.cancel()
        }
    }

    public func upload(
        _ envelope: TransferEnvelope,
        fromFile: URL,
        progress: @Sendable @escaping (Int64, Int64) -> Void
    ) async throws -> String? {
        var request = URLRequest(url: envelope.url)
        request.httpMethod = envelope.method
        for (name, value) in envelope.headers { request.setValue(value, forHTTPHeaderField: name) }

        let observer = ProgressObserver(progress: progress)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.uploadTask(with: request, fromFile: fromFile) { _, response, error in
                    if let error { return continuation.resume(throwing: error) }
                    guard let http = response as? HTTPURLResponse else {
                        return continuation.resume(throwing: MediaTransferError.providerUnavailable(status: 0))
                    }
                    if let failure = Self.failure(for: http.statusCode) {
                        return continuation.resume(throwing: failure)
                    }
                    continuation.resume(returning: http.value(forHTTPHeaderField: "ETag"))
                }
                task.delegate = observer
                observer.task = task
                task.resume()
            }
        } onCancel: {
            observer.task?.cancel()
        }
    }

    /// Maps provider status codes onto the typed reasons the UI can explain.
    private static func failure(for status: Int) -> MediaTransferError? {
        switch status {
        case 200..<300: return nil
        // an expired presigned URL; the downloader refetches once before surfacing this
        case 401, 403: return .linkExpired
        case 404: return .gone
        default: return .providerUnavailable(status: status)
        }
    }
}

/// Forwards byte counts from a task. Throttled to ~1% so a 200 MB download does not push hundreds of
/// updates a second into SwiftUI state.
private final class ProgressObserver: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate, @unchecked Sendable {

    private let progress: @Sendable (Int64, Int64) -> Void
    private var lastReported: Int64 = 0
    weak var task: URLSessionTask?

    init(progress: @Sendable @escaping (Int64, Int64) -> Void) {
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        report(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        report(totalBytesSent, totalBytesExpectedToSend)
    }

    /// Required by `URLSessionDownloadDelegate`; the completion handler owns the file instead.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    private func report(_ done: Int64, _ total: Int64) {
        guard total > 0 else { return }
        let step = max(total / 100, 64 * 1024)
        guard done - lastReported >= step || done == total else { return }
        lastReported = done
        progress(done, total)
    }
}
