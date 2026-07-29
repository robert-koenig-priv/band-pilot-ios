import SwiftUI
import BandPilotKit

/// Lists a song's media links grouped by type. YouTube/Audio push an in-app player;
/// Video/SoundCloud/Spotify open externally.
struct MediaSheet: View {
    let song: Song
    let links: [MediaLink]
    let bandId: Int
    let vm: BandDetailViewModel
    let library: MediaLibrary
    @State private var path: [MediaLink]
    @State private var openedFile: MediaFile?
    @State private var showUpload = false
    /// The item a delete has been asked for but not yet confirmed. One optional per kind rather than one
    /// enum, because the confirmation wording differs: a file is recoverable, a link is not.
    @State private var confirmingLink: MediaLink?
    @State private var confirmingFile: MediaFile?
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    init(song: Song, links: [MediaLink], bandId: Int, vm: BandDetailViewModel, library: MediaLibrary) {
        self.song = song
        self.links = links
        self.bandId = bandId
        self.vm = vm
        self.library = library
        #if DEBUG
        let want = ProcessInfo.processInfo.environment["BP_OPEN_PLAYER"]
        if want == "youtube", let first = links.first(where: { $0.mediaType == .youtube }) {
            _path = State(initialValue: [first])
        } else if want == "audio", let first = links.first(where: { $0.mediaType == .audio }) {
            _path = State(initialValue: [first])
        } else {
            _path = State(initialValue: [])
        }
        #else
        _path = State(initialValue: [])
        #endif
    }

    /// Links carry the same owner tag as files, so the one filter governs both lists.
    private var visibleLinks: [MediaLink] {
        links.filter { vm.ownerFilter.includes($0, myBandMemberId: vm.myBandMemberId) }
    }

    private var grouped: [(type: MediaType, items: [MediaLink])] {
        MediaType.allCases.compactMap { type in
            let items = visibleLinks.filter { $0.mediaType == type }
            return items.isEmpty ? nil : (type, items)
        }
    }

    /// The player's up-next list, which must match what the list actually offered — otherwise swiping
    /// on inside the player produces a video the sheet had filtered away.
    private var youtubeLinks: [MediaLink] { visibleLinks.filter { $0.mediaType == .youtube } }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Palette.bg.ignoresSafeArea()
                List {
                    ForEach(grouped, id: \.type) { group in
                        Section {
                            ForEach(group.items) { link in row(group.type, link) }
                        } header: {
                            Text(group.type.label).foregroundStyle(Palette.textDim)
                        }
                    }

                    // Files after links: links are references, files are the band's own material and
                    // the only thing that works offline.
                    ForEach(groupedFiles, id: \.kind) { group in
                        Section {
                            ForEach(group.items) { file in fileRow(file) }
                        } header: {
                            Text(group.kind.label).foregroundStyle(Palette.textDim)
                        }
                    }

                    if canUpload {
                        Section {
                            Button {
                                showUpload = true
                            } label: {
                                Label("Add file", systemImage: "arrow.up.doc")
                                    .foregroundStyle(Palette.accent)
                            }
                            .listRowBackground(Palette.bgCard)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Palette.bg)
            }
            .navigationTitle(song.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                // One control for the whole sheet. It used to sit in each file-kind section header, which
                // worked while files were the only owned thing; now that links are owned too it would
                // repeat across up to eight headers and read as eight separate filters.
                if showOwnerFilter {
                    ToolbarItem(placement: .primaryAction) {
                        Button(vm.ownerFilter.label) {
                            vm.ownerFilter = vm.ownerFilter == .mineAndBand ? .everyone : .mineAndBand
                        }
                        .foregroundStyle(Palette.accent)
                    }
                }
            }
            .navigationDestination(for: MediaLink.self) { link in
                switch link.mediaType {
                case .youtube:
                    YouTubePlayerScreen(links: youtubeLinks, initial: link, songTitle: song.name)
                case .audio:
                    if let url = URL(string: link.url.trimmingCharacters(in: .whitespaces)) {
                        AudioPracticePlayerScreen(song: song, url: url)
                    } else {
                        Text("Invalid audio URL.").foregroundStyle(Palette.textDim)
                    }
                default:
                    EmptyView()
                }
            }
            .navigationDestination(item: $openedFile) { file in
                MediaFileGate(bandId: bandId, song: song, file: file, library: library)
            }
            .sheet(isPresented: $showUpload) {
                MediaUploadSheet(bandId: bandId, song: song, vm: vm, library: library)
            }
            // Two confirmations rather than one, because the consequence differs and that difference is
            // the whole of the user's decision: a file comes back, a link does not.
            .confirmationDialog(
                "Delete \(confirmingLink?.name ?? "")?",
                isPresented: .init(get: { confirmingLink != nil }, set: { if !$0 { confirmingLink = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let link = confirmingLink { Task { await vm.deleteLink(link) } }
                    confirmingLink = nil
                }
                Button("Cancel", role: .cancel) { confirmingLink = nil }
            } message: {
                Text(
                    "This link will be gone for good — there is no undo. The page it points at is "
                        + "unaffected, so it can be added again."
                )
            }
            .confirmationDialog(
                "Delete \(confirmingFile?.name ?? "")?",
                isPresented: .init(get: { confirmingFile != nil }, set: { if !$0 { confirmingFile = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let file = confirmingFile { Task { await vm.deleteFile(file, library: library) } }
                    confirmingFile = nil
                }
                Button("Cancel", role: .cancel) { confirmingFile = nil }
            } message: {
                Text(
                    "This removes the file from the band's list. An admin can still restore it for a "
                        + "while before its contents are deleted from storage for good."
                )
            }
        }
        .tint(Palette.selected)
    }

    private var visibleFiles: [MediaFile] {
        vm.files(for: song.id).filter { vm.ownerFilter.includes($0, myBandMemberId: vm.myBandMemberId) }
    }

    private var groupedFiles: [(kind: MediaFileKind, items: [MediaFile])] {
        MediaFileKind.allCases.compactMap { kind in
            let items = visibleFiles.filter { $0.kind == kind }
            return items.isEmpty ? nil : (kind, items)
        }
    }

    /// Only offered when it would change what is on screen — otherwise it is permanent noise. Weighed
    /// against the *unfiltered* lists, so switching to "Mine" cannot make the button that switches back
    /// disappear.
    private var showOwnerFilter: Bool {
        guard let mine = vm.myBandMemberId else { return false }
        let someoneElses = { (owner: Int?) in owner != nil && owner != mine }
        return vm.files(for: song.id).contains { someoneElses($0.ownerBandMemberId) }
            || links.contains { someoneElses($0.ownerBandMemberId) }
    }

    /// Role only — deliberately NOT ``canUpload``, which additionally requires a configured bucket.
    /// Re-tagging and deleting a *link* touch no storage at all, so gating them on the bucket would leave
    /// a band that has not set one up unable to tidy its own YouTube links.
    private var canManageMedia: Bool { Permissions.canUploadMedia(vm.myRole) }

    private var canUpload: Bool {
        vm.mediaFilesSupported
            && Permissions.canUploadMedia(vm.myRole)
            && vm.uploadPolicy?.canUpload == true
    }

    /// The cached badge is the trust signal: the value of the cache is that people rely on it at a venue
    /// with no signal, and that has to be visible.
    @ViewBuilder private func fileRow(_ file: MediaFile) -> some View {
        Button {
            openedFile = file
        } label: {
            HStack(spacing: 10) {
                Image(systemName: fileIcon(file))
                    .foregroundStyle(Palette.selected)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name).foregroundStyle(Palette.text)
                    Text(subtitle(for: file)).font(.caption).foregroundStyle(Palette.textDim)
                }
                Spacer()
                switch library.state(for: file) {
                case .cached:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent)
                case .transferring(let fraction, _, _):
                    ProgressView(value: fraction).frame(width: 40).tint(Palette.accent)
                case .failed, .unavailable:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.danger)
                case .absent:
                    Image(systemName: "arrow.down.circle").foregroundStyle(Palette.textDim)
                }
            }
        }
        .listRowBackground(Palette.bgCard)
        .mediaItemActions(
            enabled: canManageMedia,
            label: file.name,
            ownedByMe: file.ownerBandMemberId != nil && file.ownerBandMemberId == vm.myBandMemberId,
            canClaim: vm.myBandMemberId != nil,
            onSetOwner: { owner in Task { await vm.setFileOwner(file, to: owner) } },
            myBandMemberId: vm.myBandMemberId,
            onDeleteRequested: { confirmingFile = file }
        )
    }

    private func subtitle(for file: MediaFile) -> String {
        let mb = Double(file.sizeBytes) / 1_048_576
        let size = mb >= 0.1 ? String(format: "%.1f MB", mb) : "\(file.sizeBytes / 1024) KB"
        if case .failed(let message) = library.state(for: file) { return message }
        if case .unavailable = library.state(for: file) { return "No longer available" }
        guard let nick = ownerNick(file.ownerBandMemberId) else { return size }
        return "\(size) · for \(nick)"
    }

    /// Whose it is, or nil for the band's own — and also nil for an owner no longer on the roster, where
    /// "for Unknown" would be worse than saying nothing.
    private func ownerNick(_ ownerBandMemberId: Int?) -> String? {
        guard let owner = ownerBandMemberId else { return nil }
        return vm.roster.first(where: { $0.id == owner })?.nickName
    }

    private func fileIcon(_ file: MediaFile) -> String {
        switch file.viewer {
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        case .audio: return "waveform"
        case .video: return "video.fill"
        case .unsupported: return "doc"
        }
    }

    @ViewBuilder private func row(_ type: MediaType, _ link: MediaLink) -> some View {
        Group {
            if type.playsInApp {
                NavigationLink(value: link) { label(type, link) }
            } else {
                Button {
                    if let url = URL(string: link.url.trimmingCharacters(in: .whitespaces)) { openURL(url) }
                } label: {
                    HStack {
                        label(type, link)
                        Spacer()
                        Image(systemName: "arrow.up.right.square").foregroundStyle(Palette.textDim)
                    }
                }
            }
        }
        .listRowBackground(Palette.bgCard)
        .mediaItemActions(
            enabled: canManageMedia,
            label: link.name,
            ownedByMe: link.ownerBandMemberId != nil && link.ownerBandMemberId == vm.myBandMemberId,
            canClaim: vm.myBandMemberId != nil,
            onSetOwner: { owner in Task { await vm.setLinkOwner(link, to: owner) } },
            myBandMemberId: vm.myBandMemberId,
            onDeleteRequested: { confirmingLink = link }
        )
    }

    private func label(_ type: MediaType, _ link: MediaLink) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(type)).foregroundStyle(Palette.selected).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(link.name).foregroundStyle(Palette.text)
                if let nick = ownerNick(link.ownerBandMemberId) {
                    Text("for \(nick)").font(.caption).foregroundStyle(Palette.textDim)
                }
            }
        }
    }

    private func icon(_ type: MediaType) -> String {
        switch type {
        case .youtube: return "play.rectangle.fill"
        case .audio: return "waveform"
        case .video: return "video.fill"
        case .soundcloud: return "cloud.fill"
        case .spotify: return "music.note"
        }
    }
}
