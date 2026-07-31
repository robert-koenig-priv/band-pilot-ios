import SwiftUI
import BandPilotKit

/// Stacks whichever header panels are open, in `HeaderSection.allCases` order.
///
/// No card behind them: each chip carries its own pill, so a panel is just these rows on the page
/// background — as on Android.
struct SongsHeader: View {
    let state: SongsHeaderState
    let flagsInUse: [Flag]

    var body: some View {
        if !state.visibleSections.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(HeaderSection.allCases, id: \.self) { section in
                    if state.visibleSections.contains(section) { row(section) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder private func row(_ section: HeaderSection) -> some View {
        switch section {
        case .details: DetailChips(state: state, flagsInUse: flagsInUse)
        case .sort: SortChips(state: state)
        case .filter: FilterChips(state: state, flagsInUse: flagsInUse)
        case .group, .search:
            // Tasks 7 and 8.
            HStack(spacing: 6) {
                SectionGlyph(section: section) { state.toggle(section) }
                Text(section.label).font(.footnote).foregroundStyle(Palette.textDim)
            }
        }
    }
}
