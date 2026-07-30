import SwiftUI
import BandPilotKit

struct BandsView: View {
    let session: SessionStore
    let api: APIClient
    let library: MediaLibrary
    let shell: ShellState
    @State private var vm: BandsViewModel

    init(session: SessionStore, api: APIClient, library: MediaLibrary, shell: ShellState) {
        self.library = library
        self.session = session
        self.api = api
        self.shell = shell
        _vm = State(wrappedValue: BandsViewModel(api: api))
    }

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            content
        }
        .navigationTitle("Bands")
        .drawerToolbar(shell)
        .task { await vm.load() }
    }

    @ViewBuilder private var content: some View {
        if vm.isLoading && vm.bands.isEmpty {
            ProgressView().tint(Palette.textDim)
        } else if let error = vm.error {
            VStack(spacing: 12) {
                ErrorBanner(message: error.userMessage, waking: error.isBackendWaking)
                Button("Retry") { Task { await vm.load() } }
                    .foregroundStyle(Palette.selected)
            }
            .padding(24)
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(vm.bands) { band in
                        // A button rather than a NavigationLink so the band's name reaches the
                        // drawer at the moment of the tap — it is in hand here, which spares the
                        // drawer a fetch of its own.
                        Button {
                            shell.rememberBand(id: band.id, name: band.name)
                            shell.open(.songs(bandId: band.id))
                        } label: {
                            BandRow(band: band)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct BandRow: View {
    let band: Band

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Palette.bgSoft)
                Circle().stroke(Palette.line, lineWidth: 1)
                Text(initials).font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.textDim)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(band.name).font(.bebas(22)).foregroundStyle(Palette.text)
                    if let role = roleLabel {
                        Text("(\(role))").font(.footnote).foregroundStyle(Palette.textDim)
                    }
                }
                if let tagline = band.tagline {
                    Text(tagline).font(.subheadline).foregroundStyle(Palette.textDim)
                }
                if let location = band.location {
                    Text(location).font(.subheadline).foregroundStyle(Palette.textDim)
                }
            }
            Spacer(minLength: 0)
            if band.homepage != nil {
                Image(systemName: "house").foregroundStyle(Palette.textDim)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line, lineWidth: 1))
    }

    private var initials: String {
        String(band.name.replacingOccurrences(of: " ", with: "").prefix(2)).uppercased()
    }

    /// Show the role except plain MEMBER (matches Android: only call out elevated/reduced roles).
    private var roleLabel: String? {
        switch band.securityRole {
        case .globalAdmin: return "Global admin"
        case .admin: return "Admin"
        case .editor: return "Editor"
        case .guest: return "Guest"
        case .member, .none: return nil
        }
    }
}
