import SwiftUI
import BandPilotKit

/// One group's row in the songlist: a rotating chevron, an optional flag dot, the label, and the count.
///
/// A tinted row rather than indenting the songs beneath it — indentation costs width the song names
/// need.
struct GroupHeader: View {
    let group: SongGroup
    let collapsed: Bool
    let isWide: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.textDim)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                if let flag = group.flag {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(hexString: flag.color))
                }
                VStack(alignment: .leading, spacing: 2) {
                    if isWide, let d = group.flag?.description, !d.isEmpty {
                        HStack(spacing: 8) {
                            Text(group.label).font(.headline).foregroundStyle(Palette.text)
                            Text(d).font(.caption).foregroundStyle(Palette.textDim)
                        }
                    } else {
                        Text(group.label).font(.headline).foregroundStyle(Palette.text)
                        if let d = group.flag?.description, !d.isEmpty {
                            Text(d).font(.caption).foregroundStyle(Palette.textDim)
                        }
                    }
                }
                Spacer(minLength: 0)
                Text("\(group.songs.count)")
                    .font(.body.bold())
                    .foregroundStyle(Palette.selected)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(collapsed ? "Expand group" : "Collapse group")
    }
}
