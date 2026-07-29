import Foundation

extension Endpoint {
    /// Per-song media links (there is no bulk-per-band read).
    public static func mediaLinks(bandId: Int, songId: Int) -> Endpoint<[MediaLink]> {
        .init(method: .get, path: "api/bands/\(bandId)/songs/\(songId)/media-links")
    }

    /// Re-tag or rename a link. Adding one is still web-UI only — it needs a URL typed in.
    public static func updateMediaLink(
        bandId: Int,
        songId: Int,
        linkId: Int,
        _ req: MediaLinkRequest
    ) -> Endpoint<MediaLink> {
        .init(method: .put, path: "api/bands/\(bandId)/songs/\(songId)/media-links/\(linkId)", body: req)
    }

    /// ⚠️ Permanent — a link has no soft delete or restore, unlike a media file.
    public static func deleteMediaLink(bandId: Int, songId: Int, linkId: Int) -> Endpoint<EmptyResponse> {
        .init(method: .delete, path: "api/bands/\(bandId)/songs/\(songId)/media-links/\(linkId)")
    }
}
