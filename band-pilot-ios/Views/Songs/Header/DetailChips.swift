import SwiftUI
import BandPilotKit

/// Which optional attributes the cards show. Eight chips at a tighter 3pt spacing, so as many as
/// possible fit one phone width.
///
/// Written as an explicit sequence rather than a `SongDetail.allCases` loop: Media leads, and the
/// Flag and Rating chips are not `SongDetail` cases at all, so folding them into an index-based
/// `ForEach` (slot Rating in "after index 1") is fragile to read and to reorder. Spelling out the
/// eight chips in place keeps the required order — Flag, Media, Rating, Status, Artist, Key, BPM,
/// Duration — visible at the call site.
struct DetailChips: View {
    let state: SongsHeaderState
    let flagsInUse: [Flag]

    var body: some View {
        HStack(spacing: 0) {
            SectionGlyph(section: .details) { state.toggle(.details) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    if !flagsInUse.isEmpty { flagChip }
                    detailChip(.media)
                    ratingChip
                    detailChip(.status)
                    detailChip(.artist)
                    detailChip(.key)
                    detailChip(.bpm)
                    detailChip(.duration)
                }
            }
        }
    }

    private func detailChip(_ detail: SongDetail) -> some View {
        HeaderChip { state.toggleDetail(detail) } content: {
            ChipLabel(
                systemImage: detail.systemImage,
                text: detail.chipText ?? detail.label,
                isSelected: state.visibleDetails.contains(detail)
            )
        }
    }

    /// One boolean for every flag, not one per flag: Android tried per-flag switches and removed them.
    private var flagChip: some View {
        HeaderChip { state.toggleFlagsVisible() } content: {
            ChipLabel(systemImage: "flag.fill", text: "Flag", isSelected: state.flagsVisible)
        }
    }

    private var ratingChip: some View {
        HeaderChip { state.cycleRatingDisplay() } content: {
            ChipLabel(
                systemImage: state.ratingDisplay.systemImage,
                text: "Rating",
                isSelected: state.ratingDisplay != .hidden
            )
            .accessibilityLabel(state.ratingDisplay.accessibilityLabel)
        }
    }
}
