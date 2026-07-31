import SwiftUI
import BandPilotKit

struct SongsView: View {
    @State private var vm: BandDetailViewModel
    let library: MediaLibrary
    let shell: ShellState
    @Environment(\.isWide) private var isWide

    @State private var editingSong: Song?
    @State private var votingSongId: Int?
    @State private var mediaSong: Song?

    private var derivedSongs: [Song] {
        SongSorting.sorted(vm.songs, by: .rating, descending: false, ratingOf: \.averageRating)
    }

    init(bandId: Int, currentUserId: Int, api: APIClient, library: MediaLibrary, shell: ShellState) {
        self.library = library
        self.shell = shell
        _vm = State(wrappedValue: BandDetailViewModel(bandId: bandId, currentUserId: currentUserId, api: api))
    }

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            content
        }
        // The page label, as Android's bar shows — the band name lives in the drawer's band section.
        // This is the nav-bar width the songs control bars need.
        .navigationTitle("Songs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(derivedSongs.count)").foregroundStyle(Palette.textDim)
            }
        }
        .drawerToolbar(shell)
        .task {
            await vm.load()
            // The drawer's band heading, refreshed from the page that actually fetched the band.
            // BandsView already supplies the name on tap, so this is normally a no-op — but a deep
            // link (BP_OPEN_BAND) arrives with no name at all, and Android likewise shows the name
            // as soon as its own fetch lands rather than leaving the "BAND" placeholder up.
            if let name = vm.band?.name { shell.rememberBand(id: vm.bandId, name: name) }
            // one band-scoped call; a 404 degrades to links-only rather than erroring
            await vm.loadMediaFiles(library: library)
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            if env["BP_OPEN_VOTING"] == "1" { votingSongId = derivedSongs.first?.id }
            if env["BP_OPEN_EDIT"] == "1" { editingSong = derivedSongs.first }
            if env["BP_OPEN_MEDIA"] == "1" {
                for song in derivedSongs {
                    await vm.ensureMediaLoaded(songId: song.id)
                    if vm.hasMedia(song.id) { mediaSong = song; break }
                }
            }
            if let raw = env["BP_OPEN_MEDIA_SONG"], let sid = Int(raw) {
                await vm.ensureMediaLoaded(songId: sid)
                if let song = vm.songs.first(where: { $0.id == sid }) { mediaSong = song }
            }
            #endif
        }
        .sheet(item: $editingSong) { song in
            SongEditSheet(vm: vm, song: song)
        }
        .sheet(item: $mediaSong) { song in
            MediaSheet(
                song: song,
                links: vm.media(for: song.id),
                bandId: vm.bandId,
                vm: vm,
                library: library
            )
        }
    }

    @ViewBuilder private var content: some View {
        if vm.isLoading && vm.songs.isEmpty {
            ProgressView().tint(Palette.textDim)
        } else if let error = vm.error, vm.songs.isEmpty {
            VStack(spacing: 12) {
                ErrorBanner(message: error.userMessage, waking: error.isBackendWaking)
                Button("Retry") { Task { await vm.load() } }.foregroundStyle(Palette.selected)
            }
            .padding(24)
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(derivedSongs) { song in
                            SongRow(
                                vm: vm,
                                song: song,
                                isWide: isWide,
                                isVotingOpen: votingSongId == song.id,
                                onToggleVoting: {
                                    votingSongId = (votingSongId == song.id) ? nil : song.id
                                },
                                onEdit: { editingSong = song },
                                onMedia: { mediaSong = song }
                            )
                            Divider().overlay(Palette.line)
                        }
                    }
                }
            }
        }
    }
}
