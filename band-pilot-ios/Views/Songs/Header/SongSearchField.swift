import SwiftUI
import BandPilotKit

/// The search field.
///
/// Hand-built rather than `.searchable`, which puts its field in the nav bar — already full — and
/// offers no way to make the leading magnifier close the section, which is how every other panel here
/// behaves.
struct SongSearchField: View {
    let state: SongsHeaderState
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // The magnifier is this panel's section glyph: tapping it closes the panel.
            Button { state.toggle(.search) } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.textDim)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide search")

            TextField("Song or artist…", text: Binding(
                get: { state.search },
                set: { state.search = $0 }
            ))
            .focused($focused)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .foregroundStyle(Palette.text)
            .tint(Palette.selected)

            if !state.search.isEmpty {
                Button { state.search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.textDim)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.bgSoft)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear { focused = true }
    }
}
