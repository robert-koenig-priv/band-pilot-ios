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

/// A named, typed link on a song (`GET .../songs/{id}/media-links`).
public struct MediaLink: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let songId: Int
    public let name: String
    public let mediaType: MediaType
    public let url: String
}
