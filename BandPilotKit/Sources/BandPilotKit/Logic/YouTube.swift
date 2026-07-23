import Foundation

public enum YouTube {
    /// The video id from a YouTube URL (watch/youtu.be/shorts/embed/live/v forms), or nil when the
    /// URL isn't recognizably a YouTube video — mirrors the Android `youTubeVideoId`.
    public static func videoId(from urlString: String) -> String? {
        guard let comps = URLComponents(string: urlString.trimmingCharacters(in: .whitespaces)) else { return nil }
        var host = (comps.host ?? "").lowercased()
        for prefix in ["www.", "m.", "music."] where host.hasPrefix(prefix) {
            host = String(host.dropFirst(prefix.count))
        }
        let segments = comps.path.split(separator: "/").map(String.init)
        var id: String?
        if host == "youtu.be" {
            id = segments.first
        } else if host == "youtube.com" {
            switch segments.first {
            case "watch": id = comps.queryItems?.first { $0.name == "v" }?.value
            case "shorts", "embed", "live", "v": id = segments.count > 1 ? segments[1] : nil
            default: id = nil
            }
        }
        guard let candidate = id,
              candidate.range(of: "^[A-Za-z0-9_-]{5,20}$", options: .regularExpression) != nil
        else { return nil }
        return candidate
    }

    /// The inline IFrame embed URL for a video id.
    public static func embedURL(_ videoId: String) -> URL? {
        URL(string: "https://www.youtube.com/embed/\(videoId)?playsinline=1&rel=0")
    }
}
