import SwiftUI
import BandPilotKit

struct BandSongsView: View {
    @State private var vm: BandDetailViewModel
    @Environment(\.isWide) private var isWide

    @State private var editingSong: BandSong?
    @State private var votingSongId: Int?
    @State private var mediaSong: BandSong?

    init(bandId: Int, currentUserId: Int, api: APIClient) {
        _vm = State(wrappedValue: BandDetailViewModel(bandId: bandId, currentUserId: currentUserId, api: api))
    }

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            content
        }
        .navigationTitle(vm.band?.name ?? "Songs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppRoute.rehearsals(bandId: vm.bandId)) {
                    Image(systemName: "calendar")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(vm.visibleSongs.count)").foregroundStyle(Palette.textDim)
            }
        }
        .task {
            await vm.load()
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            if env["BP_OPEN_VOTING"] == "1" { votingSongId = vm.visibleSongs.first?.id }
            if env["BP_OPEN_EDIT"] == "1" { editingSong = vm.visibleSongs.first }
            if env["BP_OPEN_MEDIA"] == "1" {
                for song in vm.visibleSongs {
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
            MediaSheet(song: song, links: vm.media(for: song.id))
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
                FilterSortBar(vm: vm)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.visibleSongs) { song in
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

/// Status filter chips (exclusive; tapping the active one clears) + a sort menu.
private struct FilterSortBar: View {
    @Bindable var vm: BandDetailViewModel

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All", active: vm.statusFilter == nil) { vm.statusFilter = nil }
                    ForEach(SongStatus.allCases, id: \.self) { status in
                        chip(status.label, active: vm.statusFilter == status) {
                            vm.statusFilter = (vm.statusFilter == status) ? nil : status
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            Menu {
                Picker("Sort", selection: $vm.sort) {
                    Text("Rating").tag(SongSort.practiceOrder)
                    Text("Song").tag(SongSort.name)
                    Text("Artist").tag(SongSort.artist)
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundStyle(Palette.selected)
                    .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 10)
        .background(Palette.bgSoft)
    }

    private func chip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Palette.bg : Palette.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(active ? AnyShapeStyle(Palette.selected) : AnyShapeStyle(Palette.bgCard))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Palette.line, lineWidth: active ? 0 : 1))
        }
    }
}
