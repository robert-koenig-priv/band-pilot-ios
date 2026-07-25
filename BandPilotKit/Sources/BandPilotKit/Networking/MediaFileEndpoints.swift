import Foundation

/// Media-file routes.
///
/// Band-scoped with an optional song filter rather than nested under a song, because a file need not
/// belong to one — and one band-scoped read avoids the per-song fan-out that `mediaLinks` still pays,
/// which matters against a backend that sleeps after 15 minutes.
extension Endpoint {
    public static func mediaFiles(bandId: Int) -> Endpoint<[MediaFile]> {
        .init(method: .get, path: "api/bands/\(bandId)/media-files")
    }

    public static func mediaUploadPolicy(bandId: Int) -> Endpoint<MediaUploadPolicy> {
        .init(method: .get, path: "api/bands/\(bandId)/media-files/upload-policy")
    }

    /// An envelope rather than a redirect: a 302 could not carry the header a future provider needs.
    public static func mediaDownloadURL(bandId: Int, fileId: Int) -> Endpoint<TransferEnvelope> {
        .init(method: .get, path: "api/bands/\(bandId)/media-files/\(fileId)/download-url")
    }

    public static func mediaUploadIntent(
        bandId: Int,
        _ req: MediaFileUploadIntentRequest
    ) -> Endpoint<MediaFileUploadIntent> {
        .init(method: .post, path: "api/bands/\(bandId)/media-files/upload-intents", body: req)
    }

    /// Idempotent, so a client that died between PUT and confirm can retry on next launch.
    public static func completeMediaUpload(bandId: Int, fileId: Int) -> Endpoint<MediaFile> {
        .init(method: .post, path: "api/bands/\(bandId)/media-files/\(fileId)/complete")
    }

    public static func deleteMediaFile(bandId: Int, fileId: Int) -> Endpoint<EmptyResponse> {
        .init(method: .delete, path: "api/bands/\(bandId)/media-files/\(fileId)")
    }
}
