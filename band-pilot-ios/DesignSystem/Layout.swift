import SwiftUI

/// True on a tablet-width screen (Android's sw600dp breakpoint). On iOS we derive it from the
/// horizontal size class (regular = iPad-class), injected once at the app root. Views read it to
/// size up rating stars/icons and show chip text labels.
private struct IsWideKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var isWide: Bool {
        get { self[IsWideKey.self] }
        set { self[IsWideKey.self] = newValue }
    }
}
