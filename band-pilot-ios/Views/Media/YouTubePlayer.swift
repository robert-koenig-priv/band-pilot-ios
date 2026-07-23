import SwiftUI
import WebKit
import BandPilotKit

/// Inline YouTube playback via the IFrame embed in a WKWebView.
struct YouTubeWebView: UIViewRepresentable {
    let videoId: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedId != videoId else { return }
        context.coordinator.loadedId = videoId
        // Use the JS IFrame Player API (as Google's youtube-ios-player-helper does) rather than a
        // bare <iframe src=embed>, which fails in WKWebView with error 152/153 due to strict
        // referrer checks. Loaded with an https baseURL so the player has a valid origin.
        let html = """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}
        #player{position:absolute;top:0;left:0;width:100%;height:100%}</style>
        </head><body>
        <div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
          var player;
          function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
              videoId: '\(videoId)',
              playerVars: { playsinline: 1, rel: 0, modestbranding: 1 }
            });
          }
        </script>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var loadedId: String? }
}

/// A YouTube link's player plus a switcher across the song's other YouTube links.
struct YouTubePlayerScreen: View {
    let links: [MediaLink]
    let songTitle: String
    @State private var current: MediaLink

    init(links: [MediaLink], initial: MediaLink, songTitle: String) {
        self.links = links
        self.songTitle = songTitle
        _current = State(initialValue: initial)
    }

    private var resolvedVideoId: String? {
        #if DEBUG
        if let test = ProcessInfo.processInfo.environment["BP_YT_TESTID"] { return test }
        #endif
        return YouTube.videoId(from: current.url)
    }

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                if let videoId = resolvedVideoId {
                    YouTubeWebView(videoId: videoId)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Text("Can't play this link.").foregroundStyle(Palette.textDim)
                }

                if links.count > 1 {
                    Picker("Version", selection: $current) {
                        ForEach(links) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(Palette.selected)
                }
                Spacer()
            }
            .padding(16)
        }
        .navigationTitle(songTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
