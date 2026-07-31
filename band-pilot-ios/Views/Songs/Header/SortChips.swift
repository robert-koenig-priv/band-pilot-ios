import SwiftUI
import BandPilotKit

/// Sort chips. Tapping the **active** chip flips the direction instead of clearing the sort — a list
/// always has an order, so there is nothing to clear to.
struct SortChips: View {
    let state: SongsHeaderState

    private let order: [SongSort] = [.name, .artist, .rating]

    var body: some View {
        HStack(spacing: 0) {
            SectionGlyph(section: .sort) { state.toggle(.sort) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(order, id: \.self) { option in
                        let isSelected = state.sort == option
                        HeaderChip { state.selectSort(option) } content: {
                            ChipLabel(
                                systemImage: symbol(option),
                                text: label(option),
                                isSelected: isSelected
                            )
                            if isSelected {
                                Image(systemName: state.sortDescending ? "chevron.down" : "chevron.up")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Palette.selected)
                                    .accessibilityLabel(state.sortDescending ? "descending" : "ascending")
                            }
                        }
                    }
                }
            }
        }
    }

    private func label(_ option: SongSort) -> String {
        switch option {
        case .name: return "Song"
        case .artist: return "Artist"
        case .rating: return "Rating"
        }
    }

    /// Song has no icon, so its chip always shows the word — there is nothing to shrink to.
    private func symbol(_ option: SongSort) -> String? {
        switch option {
        case .name: return nil
        case .artist: return "music.mic"
        case .rating: return "star.fill"
        }
    }
}
