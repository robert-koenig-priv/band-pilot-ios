import Foundation

extension Endpoint {
    /// Every link in the band, in one call — what a load uses.
    ///
    /// Overloads the per-song route below, which stays as the fallback for when this fails. Learning
    /// which songs had links used to cost a request per song, which is why the cache was filled once
    /// and never refreshed.
    public static func mediaLinks(bandId: Int) -> Endpoint<[MediaLink]> {
        .init(method: .get, path: "api/bands/\(bandId)/media-links")
    }

    /// One song's links. The fallback path — see the band-wide overload above.
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
