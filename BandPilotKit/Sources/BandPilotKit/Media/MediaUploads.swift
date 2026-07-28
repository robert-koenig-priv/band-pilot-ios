import Foundation

/// A picked file copied into our own storage, with its digests already computed.
///
/// Staging matters twice over: the document picker's URL is a short-lived security-scoped grant, so a
/// retry minutes later would find it dead; and once confirmed, this same copy is adopted into the cache,
/// so the member who uploaded never downloads their own file back.
public struct StagedUpload: Sendable {
    public let localURL: URL
    public let originalName: String
    public let sizeBytes: Int64
    public let mimeType: String
    /// content identity, and the clients' cache key
    public let sha256: String
    /// signed into the PUT so the **provider** verifies the bytes — which is why the backend never
    /// has to read them
    public let contentMd5: String

    public init(
        localURL: URL,
        originalName: String,
        sizeBytes: Int64,
        mimeType: String,
        sha256: String,
        contentMd5: String
    ) {
        self.localURL = localURL
        self.originalName = originalName
        self.sizeBytes = sizeBytes
        self.mimeType = mimeType
        self.sha256 = sha256
        self.contentMd5 = contentMd5
    }
}

/// The three-phase upload: intent, direct PUT to the band's bucket, confirm.
///
/// Lives in the package rather than the view so the sequence is one testable function instead of being
/// spread through a SwiftUI file.
public enum MediaUploads {

    /// - Returns: the confirmed file as the backend now sees it.
    public static func perform(
        api: APIClient,
        bandId: Int,
        songId: Int?,
        staged: StagedUpload,
        name: String,
        kind: MediaFileKind,
        ownerBandMemberId: Int?,
        acceptTerms: Bool,
        transfer: any FileTransferring = URLSessionFileTransfer(),
        progress: @MainActor @escaping (Double) -> Void = { _ in }
    ) async throws -> MediaFile {
        let intent = try await api.send(
            .mediaUploadIntent(
                bandId: bandId,
                MediaFileUploadIntentRequest(
                    name: name,
                    kind: kind,
                    mimeType: staged.mimeType,
                    sizeBytes: staged.sizeBytes,
                    contentMd5: staged.contentMd5,
                    sha256: staged.sha256,
                    songId: songId,
                    ownerBandMemberId: ownerBandMemberId,
                    acceptTerms: acceptTerms
                )
            )
        )

        // The envelope's headers are part of the signature, so they go out verbatim; the transfer layer
        // applies them without knowing which provider this is.
        _ = try await transfer.upload(intent.upload, fromFile: staged.localURL) { done, total in
            guard total > 0 else { return }
            let fraction = Double(done) / Double(total)
            Task { @MainActor in progress(fraction) }
        }

        // Idempotent, so a client that dies here can retry on next launch rather than orphaning the row.
        return try await api.send(.completeMediaUpload(bandId: bandId, fileId: intent.file.id))
    }
}
