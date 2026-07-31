import SwiftUI
import BandPilotKit

/// The public product/documentation site (band-pilot-home). Reads fine on a phone, so it opens
/// straight away.
private let homeSiteURL = URL(string: "https://www.bandpilot.net/")!

/// The Vue admin UI (roadie-mgt-ui) — band management this app deliberately does not offer. Opens
/// behind a choice, because its ag-Grid songlist is unusable at phone width.
let managementSiteURL = URL(string: "https://app.bandpilot.net/")!

/// The drawer's contents, top to bottom, mirroring Android's `ModalDrawerSheet`
/// (roadie-android/.../ui/RoadieApp.kt:223-395).
struct DrawerPanel: View {
    let session: SessionStore
    let library: MediaLibrary
    let shell: ShellState
    @Environment(\.openURL) private var openURL
    @State private var usedMB: Int64 = 0

    var body: some View {
        ZStack {
            // The background reaches the physical top and bottom; the content does not. Letting the
            // content ignore the safe area too puts the wordmark under the Dynamic Island.
            Palette.bgCard.ignoresSafeArea()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Recomputed on open rather than continuously: the byte count is not an observable source.
        // Android reads it per recomposition of the drawer, which comes to the same thing.
        .onChange(of: shell.isDrawerOpen, initial: true) { _, isOpen in
            if isOpen { usedMB = library.usedBytes / 1_048_576 }
        }
        // A leftward drag closes the panel. Safe next to the system back gesture, which is a
        // rightward swipe starting at the screen edge and cannot begin on an open panel.
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.width < -40 { shell.isDrawerOpen = false }
                }
        )
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BandPilotWordmark(size: 28).padding(20)

                DrawerItem("Bands", systemImage: "music.mic", isSelected: shell.selected == nil) {
                    shell.open(nil)
                }

                if let bandId = shell.currentBandId {
                    divider
                    // The band's own name in place of a static "BAND" label; a deep link that has no
                    // name yet falls back to it rather than showing nothing.
                    Text(shell.currentBandName ?? "BAND")
                        .font(.bebas(24))
                        .foregroundStyle(Palette.selected)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                    DrawerItem(
                        "Songs",
                        systemImage: "star.fill",
                        isSelected: shell.selected == .songs(bandId: bandId)
                    ) { shell.open(.songs(bandId: bandId)) }
                    DrawerItem(
                        "Rehearsal",
                        systemImage: "calendar",
                        isSelected: shell.selected == .rehearsals(bandId: bandId)
                    ) { shell.open(.rehearsals(bandId: bandId)) }
                }

                divider

                DrawerItem(systemImage: "arrow.up.forward.square", action: {
                    shell.isDrawerOpen = false
                    openURL(homeSiteURL)
                }, label: { BandPilotWordmark(size: 17, suffix: "Home") })
                DrawerHint(text: "Product Page and Documentation")

                DrawerItem(systemImage: "arrow.up.forward.square", action: {
                    shell.isDrawerOpen = false
                    shell.sheet = .managementSite
                }, label: { BandPilotWordmark(size: 17, suffix: "Web") })
                DrawerHint(text: "Manage Band on a large screen")

                divider

                if let user = session.user {
                    HStack(spacing: 12) {
                        Avatar(initials: (user.firstName.prefix(1) + user.lastName.prefix(1)).uppercased())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.fullName).foregroundStyle(Palette.text)
                            Text(user.email).font(.footnote).foregroundStyle(Palette.textDim)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                // Downloads are durable by design, which makes the app's footprint ours to show
                // rather than hide.
                DrawerItem("Storage", systemImage: "arrow.down.circle", badge: "\(usedMB) MB") {
                    shell.isDrawerOpen = false
                    shell.sheet = .storage
                }
                DrawerItem("About", systemImage: "info.circle") {
                    shell.isDrawerOpen = false
                    shell.sheet = .about
                }
                DrawerItem("Logout", systemImage: "rectangle.portrait.and.arrow.right") {
                    session.signOut()
                }

                Spacer(minLength: 24)
            }
        }
    }

    private var divider: some View {
        Divider()
            .overlay(Palette.line)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
    }
}
