import Foundation

extension Endpoint {
    /// Per-song media links (there is no bulk-per-band read).
    public static func mediaLinks(bandId: Int, songId: Int) -> Endpoint<[MediaLink]> {
        .init(method: .get, path: "api/bands/\(bandId)/songs/\(songId)/media-links")
    }
}
