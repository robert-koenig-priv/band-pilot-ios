import Foundation

/// Which backend the app talks to. Resolved once, at first access.
///
/// Precedence:
/// 1. `BP_API_BASE_URL` launch environment (DEBUG only) — the switch for day-to-day work:
///    tick/untick it in Edit Scheme › Run › Arguments, no code change. On a real device use the
///    Mac's Bonjour name rather than `localhost`, e.g. `http://your-mac.local:8080`; the
///    `NSAllowsLocalNetworking` exception in Info.plist is what permits that plain-HTTP hop.
/// 2. `BPAPIBaseURL` from Info.plist, if a build configuration supplies one.
/// 3. Built-in default: the local backend on the simulator, the deployed one on a device
///    (where `localhost` would be the phone itself).
enum AppConfig {
    static let local = URL(string: "http://localhost:8080")!
    static let deployed = URL(string: "https://roadie-service-main.onrender.com")!

    static let apiBaseURL: URL = resolveAPIBaseURL()

    private static func resolveAPIBaseURL() -> URL {
        #if DEBUG
        if let url = url(from: ProcessInfo.processInfo.environment["BP_API_BASE_URL"]) { return url }
        #endif
        if let url = url(from: Bundle.main.object(forInfoDictionaryKey: "BPAPIBaseURL") as? String) {
            return url
        }
        #if targetEnvironment(simulator)
        return local
        #else
        return deployed
        #endif
    }

    private static func url(from raw: String?) -> URL? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}
