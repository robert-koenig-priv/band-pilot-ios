import SwiftUI
import BandPilotKit

/// Status chips plus a flag chip. Statuses and flags are one exclusive radio group: picking either
/// clears the other, so the list is never narrowed two ways at once with only one chip to show it.
struct FilterChips: View {
    let state: SongsHeaderState
    let flagsInUse: [Flag]
    @Environment(\.isWide) private var isWide
    @State private var flagMenuOpen = false

    /// Chip order, matching Android's STATUS_CHIP_ORDER — not the enum's declaration order.
    private let order: [SongStatus] = [.readyForStage, .needPractice, .suggested]

    private var selectedFlag: Flag? { flagsInUse.first { $0.id == state.flagFilter } }

    var body: some View {
        HStack(spacing: 0) {
            SectionGlyph(section: .filter) { state.toggle(.filter) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(order, id: \.self) { status in
                        HeaderChip { state.selectStatus(status) } content: {
                            ChipLabel(
                                systemImage: symbol(status),
                                text: status.label,
                                isSelected: state.statusFilter == status
                            )
                        }
                    }
                    if !flagsInUse.isEmpty { flagChip }
                }
            }
        }
    }

    private var flagChip: some View {
        HeaderChip { flagMenuOpen = true } content: {
            ChipLabel(
                systemImage: "flag.fill",
                text: selectedFlag?.meaning ?? "Flags",
                isSelected: selectedFlag != nil,
                // The flag's own colour, not the accent — the badge on the card is that colour too.
                selectedTint: selectedFlag.map { Color(hexString: $0.color) }
            )
        }
        .popover(isPresented: $flagMenuOpen) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(flagsInUse) { flag in
                    Button { state.selectFlag(flag.id) } label: {
                        HStack(spacing: 10) {
                            Circle().fill(Color(hexString: flag.color)).frame(width: 14, height: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(flag.meaning)
                                    .fontWeight(.semibold)
                                    // The tinted name is the only selection cue — no checkmark, as Android.
                                    .foregroundStyle(
                                        state.flagFilter == flag.id ? Palette.selected : Palette.text
                                    )
                                if let d = flag.description, !d.isEmpty {
                                    Text(d).font(.caption).foregroundStyle(Palette.textDim)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minWidth: 240)
            .background(Palette.bgCard)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func symbol(_ status: SongStatus) -> String {
        switch status {
        case .readyForStage: return "checkmark.circle.fill"
        case .needPractice: return "wrench.and.screwdriver.fill"
        case .suggested: return "questionmark.circle"
        }
    }
}
