import SwiftUI

/// Version, beta status, layout class and copyright — the counterpart of Android's `AboutDialog`.
///
/// Beta is called out next to the version and then explained, so the state of the app is visible
/// here permanently; the sign-in notice only appears once.
struct AboutSheet: View {
    @Environment(\.isWide) private var isWide
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        ZStack {
            Palette.bgCard.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 8) {
                BandPilotWordmark(size: 28).padding(.bottom, 4)
                Text("Version \(version) · Beta").foregroundStyle(Palette.text)
                Text(
                    "Still in beta and under active development — expect regular fixes, "
                        + "improvements and new features."
                )
                .font(.footnote)
                .foregroundStyle(Palette.textDim)
                Text("Layout: \(isWide ? "Tablet" : "Phone")").foregroundStyle(Palette.textDim)
                // The brand name rather than the author's own, and no legal-form suffix, since no
                // company is registered behind it yet. Copyright is unaffected by the label.
                Text("© 2026 Backline Software").foregroundStyle(Palette.textDim)

                Spacer()

                Button("OK") { dismiss() }
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(24)
        }
        .presentationDetents([.medium])
    }
}
