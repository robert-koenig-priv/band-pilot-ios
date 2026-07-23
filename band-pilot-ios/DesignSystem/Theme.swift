import SwiftUI

extension Color {
    /// 0xRRGGBB literal.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// Parse a "#RRGGBB" string (backend flag colors).
    init(hexString: String) {
        let s = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(hex: UInt32(truncatingIfNeeded: v))
    }
}

/// The dark palette, mirrored from the Android app (roadie-mgt-ui style.css).
enum Palette {
    static let bg = Color(hex: 0x0C0C10)
    static let bgSoft = Color(hex: 0x14141B)
    static let bgCard = Color(hex: 0x1B1B24)
    static let line = Color(hex: 0x2A2A36)
    static let text = Color(hex: 0xECEBF0)
    static let textDim = Color(hex: 0xA0A0B0)
    static let accent = Color(hex: 0xFF3D6E)    // pink
    static let accent2 = Color(hex: 0xFFB627)   // amber
    static let green = Color(hex: 0x3DDC84)
    static let danger = Color(hex: 0xFF3D3D)
    static let selected = Color(hex: 0x4F91FF)  // blue (focus / auth actions)

    static let accentGradient = LinearGradient(
        colors: [accent, accent2], startPoint: .leading, endPoint: .trailing
    )
    static let wordmarkGradient = LinearGradient(
        colors: [Color(hex: 0x6FC3FF), Color(hex: 0x2E5FFF)], startPoint: .leading, endPoint: .trailing
    )
}
