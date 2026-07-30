import SwiftUI
import BandPilotKit

/// The drawer's contents, top to bottom, mirroring Android's `ModalDrawerSheet`
/// (roadie-android/.../ui/RoadieApp.kt:223-395).
struct DrawerPanel: View {
    let session: SessionStore
    let library: MediaLibrary
    let shell: ShellState

    var body: some View {
        ZStack {
            // The background reaches the physical top and bottom; the content does not. Letting the
            // content ignore the safe area too puts the wordmark under the Dynamic Island.
            Palette.bgCard.ignoresSafeArea()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BandPilot")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Palette.text)
                .padding(20)

            Button("Bands") { shell.open(nil) }
                .foregroundStyle(shell.selected == nil ? Palette.selected : Palette.text)
                .padding(.horizontal, 16).padding(.vertical, 12)

            if let bandId = shell.currentBandId {
                Button("Songs") { shell.open(.songs(bandId: bandId)) }
                    .foregroundStyle(Palette.text)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                Button("Rehearsal") { shell.open(.rehearsals(bandId: bandId)) }
                    .foregroundStyle(Palette.text)
                    .padding(.horizontal, 16).padding(.vertical, 12)
            }

            Spacer()

            Button("Logout") { session.signOut() }
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
