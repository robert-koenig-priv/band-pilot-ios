import SwiftUI
import BandPilotKit

@main
struct band_pilot_iosApp: App {
    @State private var session = SessionStore()
    private let api = APIClient(baseURL: AppConfig.apiBaseURL)
    /// One library for the whole app, passed down explicitly the way `api` and `session` already are.
    private let library: MediaLibrary

    init() {
        library = MediaLibrary.live(api: api)
        _ = BrandFont.bebasName // register the bundled font early
        #if DEBUG
        print("[BandPilot] API base URL: \(AppConfig.apiBaseURL.absoluteString)")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(session: session, api: api, library: library)
                .preferredColorScheme(.dark)
                .task { await api.setTokenProvider(session) }
        }
    }
}
