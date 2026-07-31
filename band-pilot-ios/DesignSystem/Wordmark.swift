import SwiftUI

/// The BandPilot wordmark: white "Band" + the brand banner's blue gradient "Pilot", optionally
/// followed by a plain suffix so a drawer item can read "BandPilot Home".
///
/// Deliberately the system bold rather than the app's Bebas Neue. Bebas is a tall condensed display
/// face quite unlike the banner's rounded sans, so the system face is the closer match — the same
/// reasoning, and the same conclusion, as the Android app's copy of this.
struct BandPilotWordmark: View {
    var size: CGFloat = 28
    var suffix: String = ""

    var body: some View {
        HStack(spacing: 0) {
            Text("Band").foregroundStyle(Palette.text)
            Text("Pilot").foregroundStyle(Palette.wordmarkGradient)
            if !suffix.isEmpty { Text(" \(suffix)").foregroundStyle(Palette.text) }
        }
        .font(.system(size: size, weight: .bold))
    }
}
