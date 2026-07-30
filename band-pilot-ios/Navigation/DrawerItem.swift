import SwiftUI

/// One drawer row: icon, label, optional trailing badge.
///
/// The pill background marks selection (Android uses `selectedContainerColor`); an unselected row has
/// none, so the panel reads as a list rather than a stack of buttons.
struct DrawerItem<Label: View>: View {
    let systemImage: String
    var badge: String? = nil
    var isSelected: Bool = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 24)
                    .foregroundStyle(isSelected ? Palette.selected : Palette.textDim)
                // The row colours its label, so a plain-text item needs no styling of its own.
                // BandPilotWordmark is unaffected: its per-span foregroundStyle wins over this one.
                label()
                    .foregroundStyle(isSelected ? Palette.selected : Palette.text)
                Spacer(minLength: 0)
                if let badge {
                    Text(badge)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textDim)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Palette.bgSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }
}

extension DrawerItem where Label == Text {
    init(
        _ title: String,
        systemImage: String,
        badge: String? = nil,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.badge = badge
        self.isSelected = isSelected
        self.action = action
        self.label = { Text(title) }
    }
}

/// The dim explanatory line under a drawer item.
///
/// Indented to line up with the item's **label**, not its icon — Android insets it by 56dp for the
/// same reason: a hint that starts under the icon reads as a separate item.
struct DrawerHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Palette.textDim)
            .padding(.leading, 64)
            .padding(.trailing, 16)
            .padding(.bottom, 4)
    }
}
