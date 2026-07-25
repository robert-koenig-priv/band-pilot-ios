import SwiftUI
import AVFoundation
import BandPilotKit

/// AVPlayer-backed practice player with an A–B section loop (mirrors the Android Mp3PracticePlayer).
@MainActor
@Observable
final class AudioPlayerModel {
    var isPlaying = false
    var position: Double = 0
    var duration: Double = 0
    var loopA: Double?
    var loopB: Double?
    var error: String?

    @ObservationIgnored private let player: AVPlayer
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObserver: NSKeyValueObservation?

    init(url: URL) { player = AVPlayer(url: url) }

    func start() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        statusObserver = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                if item.status == .failed { self?.error = "Can't play this audio link." }
            }
        }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.position = time.seconds.isFinite ? time.seconds : 0
                if let d = self.player.currentItem?.duration.seconds, d.isFinite { self.duration = d }
                self.isPlaying = self.player.timeControlStatus == .playing
                if let a = self.loopA, let b = self.loopB, self.position >= b {
                    self.player.seek(to: CMTime(seconds: a, preferredTimescale: 600))
                }
            }
        }
        player.play()
        isPlaying = true
    }

    func stop() {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        statusObserver?.invalidate()
        statusObserver = nil
        // Release the session, or music from other apps never resumes after leaving the player. The
        // session was activated in start() and was previously never deactivated.
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func togglePlay() {
        if isPlaying {
            player.pause()
        } else {
            if duration > 0, position >= duration { player.seek(to: .zero) }
            player.play()
        }
        isPlaying.toggle()
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        position = seconds
    }

    func setA() {
        loopA = position
        if let b = loopB, b <= position { loopB = nil }
    }
    func setB() { if position > (loopA ?? 0) { loopB = position } }
    func clearLoop() { loopA = nil; loopB = nil }
}

struct AudioPracticePlayerScreen: View {
    let song: BandSong
    @State private var model: AudioPlayerModel
    @State private var dragValue: Double?

    /// Set for a cached media file rather than a streamed `MediaLink`, which changes what a playback
    /// failure means: a local file that will not play is a damaged download, not a bad URL.
    private let isLocalFile: Bool
    private let onRedownload: (() -> Void)?

    init(song: BandSong, url: URL, isLocalFile: Bool = false, onRedownload: (() -> Void)? = nil) {
        self.song = song
        self.isLocalFile = isLocalFile
        self.onRedownload = onRedownload
        _model = State(wrappedValue: AudioPlayerModel(url: url))
    }

    private var shown: Double { dragValue ?? model.position }

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text(song.artist ?? "—").foregroundStyle(Palette.textDim)
                if let error = model.error {
                    ErrorBanner(message: isLocalFile ? "This download is damaged." : error)
                    if let onRedownload {
                        Button("Remove download and try again") {
                            onRedownload()
                        }
                        .foregroundStyle(Palette.accent)
                    }
                }

                Slider(
                    value: Binding(
                        get: { min(shown, max(model.duration, 1)) },
                        set: { dragValue = $0 }
                    ),
                    in: 0...max(model.duration, 1),
                    onEditingChanged: { editing in
                        if !editing, let v = dragValue { model.seek(to: v); dragValue = nil }
                    }
                )
                .tint(Palette.accent)
                .disabled(model.duration <= 0)

                HStack {
                    Text(Self.format(shown)).font(.caption).foregroundStyle(Palette.textDim)
                    Spacer()
                    Text(Self.format(model.duration)).font(.caption).foregroundStyle(Palette.textDim)
                }

                PrimaryButton(
                    title: model.isPlaying ? "⏸  Pause" : "▶  Play",
                    fill: AnyShapeStyle(Palette.accent)
                ) { model.togglePlay() }

                Kicker("Loop section")
                HStack(spacing: 8) {
                    loopButton("A", model.loopA) { model.setA() }
                    loopButton("B", model.loopB, enabled: shown > (model.loopA ?? 0)) { model.setB() }
                    if model.loopA != nil || model.loopB != nil {
                        Button("Clear") { model.clearLoop() }.foregroundStyle(Palette.textDim)
                    }
                }
                Text(loopHint)
                    .font(.caption)
                    .foregroundStyle(model.loopA != nil && model.loopB != nil ? Palette.accent2 : Palette.textDim)

                Spacer()
            }
            .padding(20)
        }
        .navigationTitle(song.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { model.start() }
        .onDisappear { model.stop() }
    }

    private var loopHint: String {
        if model.loopA != nil, model.loopB != nil {
            return "Looping \(Self.format(model.loopA!)) – \(Self.format(model.loopB!))"
        } else if model.loopA != nil {
            return "Play or seek to the section's end, then set B."
        }
        return "Set A at the section's start to practice a part on repeat."
    }

    private func loopButton(_ label: String, _ marker: Double?, enabled: Bool = true, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(marker != nil ? "\(label) \(Self.format(marker!))" : "Set \(label)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(marker != nil ? Palette.accent2 : Palette.textDim)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(marker != nil ? Palette.accent2 : Palette.line, lineWidth: 1))
        }
        .disabled(!enabled)
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
