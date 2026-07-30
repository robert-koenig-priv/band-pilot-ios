import SwiftUI
import BandPilotKit

/// Which modal the shell is showing. Presented from the shell rather than from the drawer panel:
/// the panel is offset off-screen when closed, and a presentation owned by an off-screen view is a
/// good way to acquire a bug that only reproduces after the drawer shuts.
enum ShellSheet: String, Identifiable {
    case storage, about, managementSite
    var id: String { rawValue }
}

/// Navigation state for the signed-in app — the counterpart of Android's `RoadieAppContent`.
@Observable
final class ShellState {
    var path: [AppRoute] = []
    var isDrawerOpen = false
    var sheet: ShellSheet?

    /// The last band opened. Kept after backing out to Bands, so the drawer's band section survives
    /// the trip — Android's "the last one opened".
    ///
    /// Deliberately **not** derived from `path`: an empty path means Bands, and the band section has
    /// to outlive that. Two sources for one value is how the section would end up flickering away on
    /// the way back to Bands.
    var currentBandId: Int?
    var currentBandName: String?

    func open(_ route: AppRoute?) {
        path = ShellRouting.path(to: route)
        isDrawerOpen = false
    }

    func rememberBand(id: Int, name: String?) {
        currentBandId = id
        currentBandName = name
    }

    var selected: AppRoute? { ShellRouting.selected(in: path) }
}

/// The signed-in app: a navigation stack with a drawer over it.
///
/// The panel is a sibling of the `NavigationStack` inside the `ZStack`, not an overlay inside a
/// screen — that is what lets it cover the nav bar, which is what Android's `ModalNavigationDrawer`
/// does. It is also an ordinary view rather than a modal presentation, so it inherits the root's
/// hidden status bar and needs no `.immersive()` of its own.
struct AppShell: View {
    let session: SessionStore
    let api: APIClient
    let library: MediaLibrary
    @State private var shell = ShellState()

    init(session: SessionStore, api: APIClient, library: MediaLibrary) {
        self.session = session
        self.api = api
        self.library = library
        #if DEBUG
        // Launch-env hooks, in the same family as BP_OPEN_VOTING/BP_OPEN_EDIT: they exist so the app
        // can be driven headlessly on the simulator, where there is nothing to tap with.
        let env = ProcessInfo.processInfo.environment
        let state = ShellState()
        var seeded = false
        if let raw = env["BP_OPEN_BAND"], let id = Int(raw) {
            // A deep link knows the id but not the name, so the drawer's heading falls back to
            // "BAND" — exactly as Android does before its own band fetch lands.
            state.rememberBand(id: id, name: nil)
            state.path = ShellRouting.path(
                to: env["BP_OPEN_REHEARSALS"] == "1" ? .rehearsals(bandId: id) : .songs(bandId: id)
            )
            seeded = true
        }
        if env["BP_OPEN_DRAWER"] == "1" {
            state.isDrawerOpen = true
            seeded = true
        }
        if seeded { _shell = State(wrappedValue: state) }
        #endif
    }

    var body: some View {
        GeometryReader { proxy in
            let width = min(320, proxy.size.width - 56)
            ZStack(alignment: .leading) {
                NavigationStack(path: $shell.path) {
                    BandsView(session: session, api: api, library: library, shell: shell)
                        .navigationDestination(for: AppRoute.self) { route in
                            switch route {
                            case let .songs(bandId):
                                SongsView(
                                    bandId: bandId,
                                    currentUserId: session.user?.id ?? 0,
                                    api: api,
                                    library: library,
                                    shell: shell
                                )
                            case let .rehearsals(bandId):
                                RehearsalView(bandId: bandId, api: api, shell: shell)
                            }
                        }
                }
                .tint(Palette.selected)

                if shell.isDrawerOpen {
                    // A Button, not a bare tap gesture, so VoiceOver can reach the dismiss.
                    Button { shell.isDrawerOpen = false } label: {
                        Color.black.opacity(0.5).ignoresSafeArea()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close navigation")
                    .transition(.opacity)
                }

                DrawerPanel(session: session, library: library, shell: shell)
                    .frame(width: width)
                    .offset(x: shell.isDrawerOpen ? 0 : -width)
            }
            .animation(.easeOut(duration: 0.25), value: shell.isDrawerOpen)
        }
        .sheet(item: $shell.sheet) { sheet in
            switch sheet {
            case .storage:
                NavigationStack { MediaStorageView(library: library) }
            case .about:
                Text("About")            // Task 4
            case .managementSite:
                Text("BandPilot Web")    // Task 4
            }
        }
    }
}

extension View {
    /// The leading hamburger, defined once for every screen inside the shell.
    ///
    /// Tap only. On iOS the left screen edge is the system back gesture, so the drawer deliberately
    /// has no edge-swipe to open — and the back chevron stays where iOS users expect it, alongside
    /// this button.
    func drawerToolbar(_ shell: ShellState) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { shell.isDrawerOpen = true } label: {
                    Image(systemName: "line.3.horizontal")
                }
                .accessibilityLabel("Open navigation")
            }
        }
    }
}
