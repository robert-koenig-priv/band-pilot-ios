import SwiftUI
import BandPilotKit

@main
struct band_pilot_iosApp: App {
    @State private var session = SessionStore()
    private let api = APIClient(baseURL: URL(string: "http://localhost:8080")!)

    init() {
        _ = BrandFont.bebasName // register the bundled font early
    }

    var body: some Scene {
        WindowGroup {
            RootView(session: session, api: api)
                .preferredColorScheme(.dark)
                .task { await api.setTokenProvider(session) }
        }
    }
}
