import SwiftUI
import BandPilotKit

/// The auth gate: the session's `isAuthenticated` flips between the login screen and the app.
/// A 401 anywhere calls `SessionStore.handleUnauthorized()`, which collapses back to `AuthView`.
struct RootView: View {
    let session: SessionStore
    let api: APIClient
    let library: MediaLibrary
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if session.isAuthenticated {
                MainNavigation(session: session, api: api, library: library)
            } else {
                AuthView(session: session, api: api)
            }
        }
        .environment(\.isWide, sizeClass == .regular)
    }
}

struct MainNavigation: View {
    let session: SessionStore
    let api: APIClient
    let library: MediaLibrary
    @State private var path: [AppRoute]

    init(session: SessionStore, api: APIClient, library: MediaLibrary) {
        self.session = session
        self.api = api
        self.library = library
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let raw = env["BP_OPEN_BAND"], let id = Int(raw) {
            var initial: [AppRoute] = [.songs(bandId: id)]
            if env["BP_OPEN_REHEARSALS"] == "1" { initial.append(.rehearsals(bandId: id)) }
            _path = State(initialValue: initial)
        } else {
            _path = State(initialValue: [])
        }
        #else
        _path = State(initialValue: [])
        #endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            BandsView(session: session, api: api, library: library)
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case let .songs(bandId):
                        BandSongsView(
                            bandId: bandId,
                            currentUserId: session.user?.id ?? 0,
                            api: api,
                            library: library
                        )
                    case let .rehearsals(bandId):
                        RehearsalView(bandId: bandId, api: api)
                    }
                }
        }
        .tint(Palette.selected)
    }
}
