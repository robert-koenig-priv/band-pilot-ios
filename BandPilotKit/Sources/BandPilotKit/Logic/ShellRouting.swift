import Foundation

/// Typed navigation routes for the signed-in app.
///
/// Lives in the package rather than the app target so `ShellRouting` can be unit-tested — the
/// replace-don't-push rule below is a decision, and a decision that only exists inside a SwiftUI
/// view is a decision nothing can check.
public enum AppRoute: Hashable, Sendable {
    case songs(bandId: Int)
    case rehearsals(bandId: Int)
}

/// The navigation-path arithmetic behind the drawer.
///
/// Drawer navigation **replaces** the stack instead of pushing onto it, mirroring the Android app's
/// `popUpTo("bands")`: Songs and Rehearsal are siblings, never stacked, so the back chevron always
/// means "Bands" no matter which page you are on or how you reached it. Pushing would let the path
/// grow (songs → rehearsal → songs → …) and make back mean something different every time.
public enum ShellRouting {
    /// The entire path for a destination. `nil` is the Bands root.
    public static func path(to route: AppRoute?) -> [AppRoute] {
        guard let route else { return [] }
        return [route]
    }

    /// Which drawer item is highlighted. An empty path is the Bands root, hence `nil`.
    public static func selected(in path: [AppRoute]) -> AppRoute? {
        path.last
    }
}
