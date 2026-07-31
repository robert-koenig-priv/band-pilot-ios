import SwiftUI
import BandPilotKit

private let chipIconSize: CGFloat = 22

/// The shared header pill.
///
/// The pill's background **never changes with selection** — only the content's tint does. That is the
/// Android look, and it is why the old `FilterSortBar`, whose chips filled blue when active, is gone
/// rather than reused.
struct HeaderChip<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) { content() }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Palette.bgCard)
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Icon + optional text, tinted by selection — the body most chips want.
struct ChipLabel: View {
    let systemImage: String?
    let text: String
    let isSelected: Bool
    /// Overrides the selected tint. The Filter panel's flag chip uses the flag's own colour.
    var selectedTint: Color?
    @Environment(\.isWide) private var isWide

    private var tint: Color { isSelected ? (selectedTint ?? Palette.selected) : Palette.textDim }

    var body: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: chipIconSize * 0.8))
                .frame(height: chipIconSize)
                .foregroundStyle(tint)
                .accessibilityLabel(isWide ? "" : text)
            if isWide { Text(text).font(.footnote).foregroundStyle(tint) }
        } else {
            // No icon to shrink to, so the text always shows.
            Text(text).font(.footnote).foregroundStyle(tint)
        }
    }
}

/// The dim glyph that opens each panel row and closes that section when tapped.
///
/// Always `textDim`, never the accent: it identifies the row, it does not report a selection. No
/// leading padding — the Details row needs every point of width for its eight chips.
struct SectionGlyph: View {
    let section: HeaderSection
    let onClose: () -> Void

    var body: some View {
        Button(action: onClose) {
            Image(systemName: section.symbol)
                .font(.system(size: 16))
                .foregroundStyle(Palette.textDim)
                .padding(.vertical, 8)
                .padding(.trailing, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide \(section.label)")
    }
}

extension HeaderSection {
    var symbol: String {
        switch self {
        case .details: return "eye"
        case .sort: return "arrow.up.arrow.down"
        case .group: return "rectangle.stack"
        case .filter: return "line.3.horizontal.decrease"
        case .search: return "magnifyingglass"
        }
    }
}

/// One nav-bar toggle.
///
/// A single button rather than a view wrapping all five: a custom `View` containing a `ForEach` placed
/// in a `ToolbarItemGroup` can collapse into **one** toolbar item, which would silently give you one
/// icon where five belong. The `ForEach` therefore lives in the toolbar itself (see `SongsView`).
struct SongHeaderToggle: View {
    let section: HeaderSection
    let state: SongsHeaderState
    @Environment(\.isWide) private var isWide

    private var isOpen: Bool { state.visibleSections.contains(section) }

    var body: some View {
        Button { state.toggle(section) } label: {
            Image(systemName: section.symbol)
                .font(.system(size: isWide ? 26 : 20))
                .foregroundStyle(isOpen ? Palette.selected : Palette.textDim)
        }
        .accessibilityLabel((isOpen ? "Hide " : "Show ") + section.label)
    }
}
