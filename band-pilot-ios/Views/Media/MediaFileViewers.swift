import AVKit
import BandPilotKit
import PDFKit
import SwiftUI

/// Ensures a file's bytes are on disk, then shows the right viewer.
///
/// Pushed immediately on tap rather than blocking the row: a tap that does nothing visible for twenty
/// seconds reads as a broken app, so the destination owns the progress.
struct MediaFileGate: View {
    let bandId: Int
    let song: Song
    let file: MediaFile
    let library: MediaLibrary

    @State private var localURL: URL?

    var body: some View {
        Group {
            if let localURL {
                viewer(for: localURL)
            } else {
                switch library.state(for: file) {
                case .transferring(let fraction, let done, let total):
                    VStack(spacing: 12) {
                        ProgressView(value: fraction)
                            .tint(Palette.accent)
                        Text("\(done / 1024) KB of \(total / 1024) KB")
                            .font(.caption)
                            .foregroundStyle(Palette.textDim)
                    }
                    .padding(32)
                case .failed(let message):
                    VStack(spacing: 12) {
                        Text(message).foregroundStyle(Palette.danger).multilineTextAlignment(.center)
                        Button("Try again") {
                            library.clearFailure(file)
                            Task { localURL = await library.ensureCached(bandId: bandId, file: file) }
                        }
                    }
                    .padding(32)
                case .unavailable:
                    Text("This file is no longer available in your band's storage.")
                        .foregroundStyle(Palette.textDim)
                        .multilineTextAlignment(.center)
                        .padding(32)
                default:
                    ProgressView().tint(Palette.accent).padding(32)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg)
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // already cached? this returns instantly with no network at all
            localURL = await library.ensureCached(bandId: bandId, file: file)
        }
    }

    /// Routed by **mime type**, not by kind: a photo of a chord chart is a `.sheet` with `image/jpeg`,
    /// and handing that to PDFKit draws a blank page.
    @ViewBuilder
    private func viewer(for url: URL) -> some View {
        switch file.viewer {
        case .pdf:
            PDFDocumentView(url: url)
        case .image:
            ZoomableImageView(url: url)
        case .audio:
            AudioPracticePlayerScreen(song: song, url: url, isLocalFile: true) {
                library.removeDownload(file)
            }
        case .video:
            VideoPlayer(player: AVPlayer(url: url))
        case .unsupported:
            VStack(spacing: 8) {
                Text("Downloaded, but this app can't preview this type yet.")
                    .foregroundStyle(Palette.textDim)
                    .multilineTextAlignment(.center)
                Text(file.mimeType).font(.caption).foregroundStyle(Palette.textDim)
            }
            .padding(32)
        }
    }
}

/// A lead sheet.
///
/// `PDFView` handles pinch-zoom, panning and page navigation itself, which is the reason to prefer it
/// over rasterising pages by hand — on Android that had to be built and got it wrong twice.
///
/// `pageShadowsEnabled` is off because the drop shadows look wrong against a near-black background, and
/// the backdrop is set explicitly so a PDF's transparent background does not render as black-on-black.
struct PDFDocumentView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayDirection = .vertical
        // continuous scroll, which is what a multi-page chart wants
        view.usePageViewController(false)
        view.pageShadowsEnabled = false
        view.backgroundColor = UIColor(white: 0.12, alpha: 1)
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}

/// A photographed chart. Pinch and pan via a scroll view, which gets the gesture handling right for
/// free rather than reimplementing it.
struct ZoomableImageView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.maximumZoomScale = 6
        scroll.minimumZoomScale = 1
        scroll.bouncesZoom = true
        scroll.delegate = context.coordinator
        scroll.backgroundColor = UIColor(white: 0.12, alpha: 1)

        let imageView = UIImageView(image: UIImage(contentsOfFile: url.path))
        imageView.contentMode = .scaleAspectFit
        imageView.frame = scroll.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.addSubview(imageView)
        context.coordinator.imageView = imageView
        return scroll
    }

    func updateUIView(_ view: UIScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    }
}
