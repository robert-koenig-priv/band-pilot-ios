import BandPilotKit
import SwiftUI

/// How much space downloaded media occupies, and a way to reclaim it.
///
/// Downloads live in Application Support rather than Caches, so iOS will never silently evict a lead
/// sheet before a gig. The flip side is that the app can quietly become one of the larger things on a
/// phone, so the footprint is shown rather than hidden — and the budget is named, because an invisible
/// limit is indistinguishable from a leak.
struct MediaStorageView: View {
    let library: MediaLibrary
    @State private var used: Int64 = 0

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Kicker("Storage")
                Text("\(used / 1_048_576) MB of \(library.budgetBytes / 1_048_576) MB")
                    .foregroundStyle(Palette.text)
                ProgressView(value: budgetFraction).tint(Palette.accent)
                Text(
                    "Files you open are kept on this device so they work without a connection. "
                        + "The oldest are removed automatically when the limit is reached."
                )
                .font(.caption)
                .foregroundStyle(Palette.textDim)

                Button("Remove downloads") {
                    library.removeAllDownloads()
                    used = library.usedBytes
                }
                .foregroundStyle(Palette.danger)

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .task { used = library.usedBytes }
    }

    private var budgetFraction: Double {
        guard library.budgetBytes > 0 else { return 0 }
        return min(1, Double(used) / Double(library.budgetBytes))
    }
}
