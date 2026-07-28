import SwiftUI
import BandPilotKit

/// 1...5 star row. Pass `onSet` to make it interactive (tapping the current value clears, as Android).
/// A rating of -1 (veto) is rendered by the caller via `VetoIndicator`, not here.
struct RatingStars: View {
    let rating: Int
    var color: Color = Palette.accent2
    var size: CGFloat = 18
    var onSet: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(i <= rating ? color : Palette.line)
                    .contentShape(Rectangle())
                    .onTapGesture { onSet?(rating == i ? 0 : i) }
                    .allowsHitTesting(onSet != nil)
            }
        }
    }
}

/// The average-rating display: stars, or a veto marker when the average is -1.
struct AverageRating: View {
    let average: Double
    var size: CGFloat = 18
    var body: some View {
        if average < 0 {
            Image(systemName: "nosign")
                .font(.system(size: size))
                .foregroundStyle(Palette.danger)
        } else {
            RatingStars(rating: Int(average.rounded()), size: size)
        }
    }
}

/// Song status pill, colored by status.
struct StatusBadge: View {
    let status: SongStatus
    var body: some View {
        let c = Self.colors(status)
        Text(status.label)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(c.fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(c.bg)
            .clipShape(Capsule())
    }

    static func colors(_ s: SongStatus) -> (bg: Color, fg: Color) {
        switch s {
        case .readyForStage: return (Palette.green.opacity(0.15), Palette.green)
        case .needPractice: return (Palette.accent2.opacity(0.15), Palette.accent2)
        case .suggested: return (Palette.textDim.opacity(0.15), Palette.textDim)
        }
    }
}

/// Colored flag icons for a song, deduped by flag id (mirrors Android FlagBadges).
struct FlagBadges: View {
    let flags: [SongFlag]
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 4) {
            ForEach(deduped, id: \.id) { flag in
                Image(systemName: "flag.fill")
                    .font(.system(size: size))
                    .foregroundStyle(Color(hexString: flag.effectiveColor))
            }
        }
    }

    private var deduped: [SongFlag] {
        var seen = Set<Int>()
        var out: [SongFlag] = []
        for f in flags where !seen.contains(f.flagId) {
            seen.insert(f.flagId)
            out.append(f)
        }
        return out
    }
}
