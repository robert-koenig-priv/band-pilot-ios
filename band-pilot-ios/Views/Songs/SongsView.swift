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

    /// While a voting section is open the displayed order is frozen, so casting a vote cannot
    /// reshuffle the list under the user's thumb. Snapshotted only when a section opens *fresh*:
    /// switching straight to another song's section keeps the existing snapshot.
    @State private var frozenOrder: [Int]?
    /// Same idea for grouping — a vote must not move a song into a different group mid-tap.
    @State private var frozenGroupKeys: [Int: [String]]?

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

    /// `flagOrder` is threaded in rather than read from `flagsInUse` here, because this runs once per
    /// song inside `groupSongs`'s scan — re-deriving the dedup'd/sorted flag list on every call would
    /// make grouping O(n²) in the song count.
    private func groupKeys(for song: Song, flagOrder: [Int]) -> [String] {
        guard let groupBy = header.groupBy else { return [] }
        return SongGrouping.groupKeys(
            for: song, by: groupBy, flags: vm.flags[song.id] ?? [],
            flagOrder: flagOrder, rating: groupRating(song)
        )
    }

    /// While a voting section is open, group keys come from the frozen snapshot instead of being
    /// recomputed — otherwise a vote could move a song into a different group mid-tap.
    private func effectiveGroupKeys(for song: Song, flagOrder: [Int]) -> [String] {
        if votingSongId != nil, let frozen = frozenGroupKeys?[song.id] { return frozen }
        return groupKeys(for: song, flagOrder: flagOrder)
    }

    /// Grouping's rating is its own setting, independent of the Rating display chip.
    private func groupRating(_ song: Song) -> Double {
        guard header.groupRatingMode == .own, let me = vm.myBandMemberId else { return song.averageRating }
        return Double(vm.individualRating(songId: song.id, memberId: me))
    }

    private func groups(for songs: [Song]) -> [SongGroup] {
        guard let groupBy = header.groupBy else { return [] }
        let flagOrder = flagsInUse.map(\.id)
        return SongGrouping.groupSongs(
            songs, by: groupBy, flagsInUse: flagsInUse,
            keysOf: { self.effectiveGroupKeys(for: $0, flagOrder: flagOrder) }
        )
    }

    /// The order shown while a voting section is open is the frozen snapshot, not the live sort —
    /// otherwise casting a vote could reshuffle the list under the user's thumb. A song absent from
    /// the snapshot (added since it was taken) sorts last rather than vanishing.
    private func displayedSongs(from songs: [Song]) -> [Song] {
        guard votingSongId != nil, let frozen = frozenOrder else { return songs }
        return SongSorting.applyingFreeze(songs, frozenOrder: frozen)
    }

    /// Computes a fresh order/group-key snapshot from the *current* sort and grouping. Shared by
    /// `openVoting` (first snapshot) and `retakeFreeze` (re-snapshot on a deliberate reorder/regroup)
    /// so the logic exists in exactly one place.
    ///
    /// `uniquingKeysWith:` (keeping the first occurrence), not `uniqueKeysWithValues:`: nothing
    /// upstream guarantees song ids are unique, and a duplicate id must degrade to an odd order and
    /// never a crash — the same reasoning `SongSorting.applyingFreeze` applies to its own dictionary.
    private func snapshot() -> (order: [Int], groupKeys: [Int: [String]]?) {
        let songs = derivedSongs
        let flagOrder = flagsInUse.map(\.id)
        let order = songs.map(\.id)
        let keys: [Int: [String]]? = header.groupBy == nil
            ? nil
            : Dictionary(
                songs.map { ($0.id, groupKeys(for: $0, flagOrder: flagOrder)) },
                uniquingKeysWith: { first, _ in first }
            )
        return (order, keys)
    }

    /// Snapshots the current order/group-keys only if no voting section was already open (a fresh
    /// open); switching directly between songs' sections keeps the existing snapshot in place.
    private func openVoting(songId: Int) {
        if votingSongId == nil {
            let snap = snapshot()
            frozenOrder = snap.order
            frozenGroupKeys = snap.groupKeys
        }
        votingSongId = songId
    }

    /// Called when an ordering/grouping input changes while a voting section is open. The freeze
    /// suppresses *incidental* reordering — a vote landing while the user is just looking at the
    /// list — but must honour *deliberate* reordering the user just asked for. Discarding the freeze
    /// outright would leave the list live again until the section closes, so a vote landing in that
    /// window could still reshuffle it — exactly what the freeze exists to prevent. Retaking the
    /// snapshot from the *new* sort/grouping instead keeps both promises: the freeze stays up (a vote
    /// still cannot move anything) while reflecting the ordering/grouping the user just chose.
    private func retakeFreeze() {
        guard votingSongId != nil else { return }
        let snap = snapshot()
        frozenOrder = snap.order
        frozenGroupKeys = snap.groupKeys
    }

    /// Closing the voting section — or opening the (mutually exclusive) media sheet — lifts the freeze.
    private func closeVoting() {
        votingSongId = nil
        frozenOrder = nil
        frozenGroupKeys = nil
    }

    init(bandId: Int, currentUserId: Int, api: APIClient, library: MediaLibrary, shell: ShellState) {
        self.library = library
        self.shell = shell
        _vm = State(wrappedValue: BandDetailViewModel(bandId: bandId, currentUserId: currentUserId, api: api))
    }

    var body: some View {
        // Hoisted once per body pass: computed by `derivedSongs` above, but re-deriving it separately
        // for the nav-bar count and for the list would filter/sort the song list twice per render.
        let songs = derivedSongs
        // The nav-bar count always reflects the unfrozen list — the freeze reorders, it never filters —
        // while the list itself follows the frozen snapshot whenever a voting section is open.
        let displayed = displayedSongs(from: songs)
        ZStack {
            Palette.bg.ignoresSafeArea()
            content(derivedSongs: displayed)
        }
        // No title: back chevron + hamburger + count + Reset fill the bar; the five toggles live in
        // their own full-width row instead (see SongHeaderToggles) — the nav bar could not fit them.
        // The drawer's highlighted Songs item is what identifies the page.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(songs.count)").foregroundStyle(Palette.textDim)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { header.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                    .accessibilityLabel("Reset filters and options")
            }
        }
        .drawerToolbar(shell)
        .task {
            await vm.load()
            // Only reconcile against a load that actually succeeded. `load()` swallows its errors and
            // leaves `flags` empty on failure, so reconciling here would read "no flags exist" from a
            // network hiccup and delete a perfectly valid filter — which persists app-globally, before
            // the user can even press Retry.
            if vm.error == nil {
                header.reconcile(flagsInUse: flagsInUse)
            }
            // The drawer's band heading, refreshed from the page that actually fetched the band.
            // BandsView already supplies the name on tap, so this is normally a no-op — but a deep
            // link (BP_OPEN_BAND) arrives with no name at all, and Android likewise shows the name
            // as soon as its own fetch lands rather than leaving the "BAND" placeholder up.
            if let name = vm.band?.name { shell.rememberBand(id: vm.bandId, name: name) }
            // one band-scoped call; a 404 degrades to links-only rather than erroring
            await vm.loadMediaFiles(library: library)
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            if env["BP_OPEN_VOTING"] == "1" {
                if let id = derivedSongs.first?.id { openVoting(songId: id) }
            }
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
        .onChange(of: header.visibleDetails.contains(.media)) { _, shown in
            if !shown { mediaSong = nil }
        }
        // Every input that can change the displayed order or grouping while a voting section is open
        // retakes the freeze rather than discarding it — see `retakeFreeze()`'s doc comment for why.
        .onChange(of: header.groupBy) { _, _ in retakeFreeze() }
        .onChange(of: header.sort) { _, _ in retakeFreeze() }
        .onChange(of: header.sortDescending) { _, _ in retakeFreeze() }
        .onChange(of: header.groupRatingMode) { _, _ in retakeFreeze() }
        .onChange(of: header.ratingDisplay) { _, _ in retakeFreeze() }
    }

    @ViewBuilder private func songRow(_ song: Song) -> some View {
        SongRow(
            vm: vm,
            song: song,
            isWide: isWide,
            isVotingOpen: votingSongId == song.id,
            state: header,
            onToggleVoting: {
                if votingSongId == song.id {
                    closeVoting()
                } else {
                    openVoting(songId: song.id)
                }
            },
            onEdit: { editingSong = song },
            onMedia: {
                mediaSong = song
                closeVoting()
            }
        )
        Divider().overlay(Palette.line)
    }

    @ViewBuilder private func content(derivedSongs: [Song]) -> some View {
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
                SongHeaderToggles(state: header)
                SongsHeader(state: header, flagsInUse: flagsInUse)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // An invisible anchor at the very top. Scrolling to the first song instead
                            // would stop short whenever a group header sits above it.
                            Color.clear.frame(height: 0).id(topAnchorID)
                            if header.groupBy == nil {
                                ForEach(derivedSongs) { song in songRow(song) }
                            } else {
                                ForEach(groups(for: derivedSongs)) { group in
                                    GroupHeader(
                                        group: group,
                                        collapsed: !header.expandedGroups.contains(group.key),
                                        isWide: isWide
                                    ) {
                                        if header.expandedGroups.contains(group.key) {
                                            header.expandedGroups.remove(group.key)
                                        } else {
                                            header.expandedGroups.insert(group.key)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.top, 8)

                                    if header.expandedGroups.contains(group.key) {
                                        // Keyed by group AND song id: Flag grouping is multi-membership,
                                        // so one song legitimately appears under several groups.
                                        ForEach(group.songs) { song in
                                            songRow(song).id("\(group.key):\(song.id)")
                                        }
                                    }
                                }
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
