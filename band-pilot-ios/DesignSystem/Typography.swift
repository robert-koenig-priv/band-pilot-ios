import SwiftUI
import CoreText

enum BrandFont {
    /// Registers the bundled Bebas Neue once and returns its PostScript name.
    static let bebasName: String = {
        guard let url = Bundle.main.url(forResource: "BebasNeue-Regular", withExtension: "ttf") else {
            return "HelveticaNeue-Bold"
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        if let provider = CGDataProvider(url: url as CFURL),
           let cg = CGFont(provider),
           let ps = cg.postScriptName as String? {
            return ps
        }
        return "BebasNeue-Regular"
    }()
}

extension Font {
    /// Bebas Neue for headings/titles (falls back to a system bold if registration fails).
    static func bebas(_ size: CGFloat) -> Font {
        .custom(BrandFont.bebasName, size: size)
    }
}

/// The ".kicker" style: small, bold, wide-tracked uppercase labels.
struct Kicker: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(2)
            .foregroundStyle(Palette.textDim)
    }
}
