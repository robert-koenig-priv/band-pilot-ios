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

    @State private var header = SongsHeaderState()

    private let topAnchorID = "songs-top"

    private var flagsInUse: [Flag] { SongGrouping.flagsInUse(vm.flags) }

    /// Which rating the cards and the sort follow — the band average, or this member's own vote.
    private func ratingOf(_ song: Song) -> Double {
        guard header.ratingDisplay == .own, let me = vm.myBandMemberId else { return song.averageRating }
        return Double(vm.individualRating(songId: song.id, memberId: me))
    }

    private var derivedSongs: [Song] {
        let filtered = SongSorting.filtered(
            vm.songs,
            status: header.statusFilter,
            flagId: header.flagFilter,
            flags: vm.flags,
            search: header.search
        )
        return SongSorting.sorted(
            filtered, by: header.sort, descending: header.sortDescending, ratingOf: ratingOf
        )
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
        // No title: back chevron + hamburger + count + Reset + five toggles already fill a 402pt bar.
        // The drawer's highlighted Songs item is what identifies the page.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(derivedSongs.count)").foregroundStyle(Palette.textDim)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { header.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                    .accessibilityLabel("Reset filters and options")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                // ForEach here, not inside a wrapper view: a custom View containing a ForEach can
                // collapse into a single toolbar item.
                ForEach(HeaderSection.allCases, id: \.self) { section in
                    SongHeaderToggle(section: section, state: header)
                }
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
        .onChange(of: flagsInUse.map(\.id)) { _, _ in header.reconcile(flagsInUse: flagsInUse) }
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
                SongsHeader(state: header, flagsInUse: flagsInUse)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // An invisible anchor at the very top. Scrolling to the first song instead
                            // would stop short whenever a group header sits above it.
                            Color.clear.frame(height: 0).id(topAnchorID)
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
                    // Opening a panel, changing the sort, or resetting all jump back to the top —
                    // otherwise you are left staring at row 40 of a list you just reordered.
                    .onChange(of: header.scrollToTopTick) { _, _ in
                        withAnimation { proxy.scrollTo(topAnchorID, anchor: .top) }
                    }
                }
            }
        }
    }
}
