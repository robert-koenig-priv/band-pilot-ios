import SwiftUI

/// The ".card" style: dark panel, hairline border, rounded corners.
struct SectionCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).font(.bebas(22)).foregroundStyle(Palette.text)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line, lineWidth: 1))
    }
}

/// Labeled input with the dim kicker label and a blue focus frame.
struct LabeledField: View {
    let label: String
    @Binding var text: String
    var isSecure = false
    var keyboard: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .never
    var focusColor: Color = Palette.selected

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Kicker(label)
            Group {
                if isSecure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                }
            }
            .focused($focused)
            .keyboardType(keyboard)
            .textInputAutocapitalization(autocapitalization)
            .autocorrectionDisabled()
            .foregroundStyle(Palette.text)
            .tint(focusColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Palette.bgSoft)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(focused ? focusColor : Palette.line, lineWidth: focused ? 2 : 1)
            )
        }
    }
}

/// Primary pill button. `fill` defaults to the pink→amber brand gradient; auth screens pass blue.
struct PrimaryButton: View {
    let title: String
    var enabled = true
    var busy = false
    var fill: AnyShapeStyle = AnyShapeStyle(Palette.accentGradient)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(Palette.bg) }
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(Palette.bg)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(fill)
            .opacity(enabled && !busy ? 1 : 0.45)
            .clipShape(Capsule())
        }
        .disabled(!enabled || busy)
    }
}

/// Error / backend-waking banner.
struct ErrorBanner: View {
    let message: String
    var waking = false

    private var tint: Color { waking ? Palette.accent2 : Palette.danger }

    var body: some View {
        HStack(spacing: 8) {
            if waking { ProgressView().tint(Palette.accent2) }
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(waking ? Palette.accent2 : Color(hex: 0xFF8080))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.4), lineWidth: 1))
    }
}

/// Initials in a circle — the drawer's user row. Mirrors the Android app's `Avatar`; the app has no
/// photos in its model at all, so initials are the whole of it.
struct Avatar: View {
    let initials: String
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(Palette.bgSoft)
            Circle().stroke(Palette.line, lineWidth: 1)
            Text(initials)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(Palette.textDim)
        }
        .frame(width: size, height: size)
    }
}

/// Green sibling of ErrorBanner (the "check your email" hint).
struct InfoBanner: View {
    let message: String
    var body: some View {
        HStack {
            Text(message).font(.system(size: 14)).foregroundStyle(Palette.green)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Palette.green.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.green.opacity(0.4), lineWidth: 1))
    }
}
