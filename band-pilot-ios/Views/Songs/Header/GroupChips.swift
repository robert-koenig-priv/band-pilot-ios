import SwiftUI
import BandPilotKit

/// Group criterion chips. Single-select, and tapping the active chip clears grouping — unlike Sort,
/// "no grouping" is a real state.
struct GroupChips: View {
    let state: SongsHeaderState

    private let order: [GroupBy] = [.status, .artist, .decade, .rating, .flag]

    var body: some View {
        HStack(spacing: 0) {
            SectionGlyph(section: .group) { state.toggle(.group) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(order, id: \.self) { option in
                        let isSelected = state.groupBy == option
                        HeaderChip {
                            // Rating is a three-state cycle rather than a plain select.
                            option == .rating ? state.cycleGroupRating() : state.selectGroup(option)
                        } content: {
                            ChipLabel(
                                systemImage: symbol(option, isSelected: isSelected),
                                text: label(option, isSelected: isSelected),
                                isSelected: isSelected
                            )
                        }
                    }
                }
            }
        }
    }

    private func label(_ option: GroupBy, isSelected: Bool) -> String {
        switch option {
        case .status: return "Status"
        case .artist: return "Artist"
        case .decade: return "Decade"
        case .flag: return "Flag"
        case .rating:
            guard isSelected else { return "Rating" }
            return state.groupRatingMode == .band ? "Rating (Band)" : "Rating (Own)"
        }
    }

    private func symbol(_ option: GroupBy, isSelected: Bool) -> String {
        switch option {
        case .status: return "checkmark.circle.fill"
        case .artist: return "music.mic"
        case .decade: return "calendar"
        case .flag: return "flag.fill"
        case .rating:
            guard isSelected else { return "star.fill" }
            return state.groupRatingMode == .band ? "star.leadinghalf.filled" : "star.circle"
        }
    }
}
