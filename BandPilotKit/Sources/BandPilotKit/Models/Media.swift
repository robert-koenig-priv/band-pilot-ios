import Foundation

public enum MediaType: String, Codable, Sendable, Hashable, CaseIterable {
    case youtube = "YOUTUBE"
    case audio = "AUDIO"
    case video = "VIDEO"
    case soundcloud = "SOUNDCLOUD"
    case spotify = "SPOTIFY"

    public var label: String {
        switch self {
        case .youtube: return "YouTube"
        case .audio: return "Audio"
        case .video: return "Video"
        case .soundcloud: return "SoundCloud"
        case .spotify: return "Spotify"
        }
    }

    /// Only YouTube and Audio have in-app players; the rest open externally.
    public var playsInApp: Bool { self == .youtube || self == .audio }
}

/// Something carrying the optional owner tag. Media links and media files both do, with the same
/// meaning and the same trap, so ``MediaOwnerFilter`` is written once against this rather than twice
/// against the two types.
public protocol MediaOwnable {
    var ownerBandMemberId: Int? { get }
}

/// A named, typed link on a song (`GET .../songs/{id}/media-links`).
public struct MediaLink: Codable, Sendable, Identifiable, Hashable, MediaOwnable {
    public let id: Int
    public let songId: Int
    public let name: String
    public let mediaType: MediaType
    public let url: String
    /// **UI filtering tag only — there is no per-link permission.** Nil means the band owns the link.
    /// Every member may read and change every link whatever this says; identical contract to
    /// ``MediaFile/ownerBandMemberId``. Do not treat it as an ACL.
    ///
    /// Optional in the decoder too, so a build of this app keeps working against a backend older than
    /// the column.
    public let ownerBandMemberId: Int?
}
