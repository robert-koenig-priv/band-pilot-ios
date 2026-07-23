import SwiftUI
import BandPilotKit

/// Lists a song's media links grouped by type. YouTube/Audio push an in-app player;
/// Video/SoundCloud/Spotify open externally.
struct MediaSheet: View {
    let song: BandSong
    let links: [MediaLink]
    @State private var path: [MediaLink]
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    init(song: BandSong, links: [MediaLink]) {
        self.song = song
        self.links = links
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
        }
        .tint(Palette.selected)
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
