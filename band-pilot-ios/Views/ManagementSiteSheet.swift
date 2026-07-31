import SwiftUI

/// Open BandPilot Web here, or share the link to open it somewhere bigger — the counterpart of
/// Android's `ManagementSiteChoiceDialog`.
///
/// A sheet rather than a `confirmationDialog`, because `ShareLink` cannot be an action inside one,
/// and reaching the share sheet through a second tap on a plain alert is worse than offering both
/// directly.
///
/// Both device classes get the same opening line; only the phone is told to send the link somewhere
/// bigger, since that is the case where opening it here is the poor choice. The emphasised action
/// follows from that: Open on a tablet, Share on a phone.
struct ManagementSiteSheet: View {
    @Environment(\.isWide) private var isWide
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Palette.bgCard.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                BandPilotWordmark(size: 24, suffix: "Web")
                Text(
                    "BandPilot Web is the place to manage all the details of your band — on a "
                        + (isWide
                            ? "large screen. A tablet works, but it's at its best on a PC."
                            : "large screen. A PC or tablet is strongly recommended; it doesn't "
                                + "work well on a phone.")
                )
                .foregroundStyle(Palette.textDim)
                if !isWide {
                    Text(
                        "You're on a phone, so consider sharing the link (email, WhatsApp, …) "
                            + "and opening it on a PC — or install BandPilot on a tablet and open "
                            + "it there."
                    )
                    .foregroundStyle(Palette.textDim)
                }

                Spacer()

                HStack(spacing: 20) {
                    Spacer()
                    if isWide {
                        ShareLink(item: managementSiteURL) { Text("Share") }
                            .foregroundStyle(Palette.textDim)
                        // openURL before dismiss: dismissing first tears down the environment this
                        // action is reading out of.
                        Button("Open") { openURL(managementSiteURL); dismiss() }
                            .foregroundStyle(Palette.accent)
                            .fontWeight(.bold)
                    } else {
                        // openURL before dismiss: dismissing first tears down the environment this
                        // action is reading out of.
                        Button("Open") { openURL(managementSiteURL); dismiss() }
                            .foregroundStyle(Palette.textDim)
                        ShareLink(item: managementSiteURL) { Text("Share") }
                            .foregroundStyle(Palette.accent)
                            .fontWeight(.bold)
                    }
                }
            }
            .padding(24)
        }
        .presentationDetents([.medium])
    }
}
