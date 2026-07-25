import SwiftUI
import BandPilotKit

/// Lists a song's media links grouped by type. YouTube/Audio push an in-app player;
/// Video/SoundCloud/Spotify open externally.
struct MediaSheet: View {
    let song: BandSong
    let links: [MediaLink]
    let bandId: Int
    let vm: BandDetailViewModel
    let library: MediaLibrary
    @State private var path: [MediaLink]
    @State private var openedFile: MediaFile?
    @State private var showUpload = false
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    init(song: BandSong, links: [MediaLink], bandId: Int, vm: BandDetailViewModel, library: MediaLibrary) {
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

    private var grouped: [(type: MediaType, items: [MediaLink])] {
        MediaType.allCases.compactMap { type in
            let items = links.filter { $0.mediaType == type }
            return items.isEmpty ? nil : (type, items)
        }
    }
    private var youtubeLinks: [MediaLink] { links.filter { $0.mediaType == .youtube } }

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
                            HStack {
                                Text(group.kind.label).foregroundStyle(Palette.textDim)
                                if showOwnerFilter {
                                    Spacer()
                                    Button(vm.ownerFilter.label) {
                                        vm.ownerFilter = vm.ownerFilter == .mineAndBand ? .everyone : .mineAndBand
                                    }
                                    .font(.caption)
                                    .foregroundStyle(Palette.accent)
                                }
                            }
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

    /// Only offered when it would change what is on screen — otherwise it is permanent noise.
    private var showOwnerFilter: Bool {
        guard let mine = vm.myBandMemberId else { return false }
        return vm.files(for: song.id).contains { $0.ownerBandMemberId != nil && $0.ownerBandMemberId != mine }
    }

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
    }

    private func subtitle(for file: MediaFile) -> String {
        let mb = Double(file.sizeBytes) / 1_048_576
        let size = mb >= 0.1 ? String(format: "%.1f MB", mb) : "\(file.sizeBytes / 1024) KB"
        if case .failed(let message) = library.state(for: file) { return message }
        if case .unavailable = library.state(for: file) { return "No longer available" }
        guard let owner = file.ownerBandMemberId,
              let nick = vm.roster.first(where: { $0.id == owner })?.nickName
        else { return size }
        return "\(size) · for \(nick)"
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
        if type.playsInApp {
            NavigationLink(value: link) { label(type, link) }
                .listRowBackground(Palette.bgCard)
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
            .listRowBackground(Palette.bgCard)
        }
    }

    private func label(_ type: MediaType, _ link: MediaLink) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(type)).foregroundStyle(Palette.selected).frame(width: 22)
            Text(link.name).foregroundStyle(Palette.text)
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
