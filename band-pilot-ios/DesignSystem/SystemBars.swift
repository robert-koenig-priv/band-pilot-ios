import SwiftUI

/// This app runs immersive: the status bar is hidden — no clock, no battery, no signal — and the home
/// indicator is allowed to fade away. The Android app does the same (`ui/components/SystemBars.kt`), so
/// this is parity, not a separate decision.
///
/// Not a stylistic choice there and not here: the app's job on stage is to show a songlist or a lead
/// sheet, and the status bar costs screen height for information nobody needs mid-song. iOS keeps it one
/// swipe-down away, so nothing is actually taken from the user.
///
/// One call at the app's root covers everything the app presents today: every modal here is a page
/// `sheet`, which does not cover the full screen, so the root view keeps owning the status-bar
/// preference — verified on the simulator with the media sheet open. A `fullScreenCover` would be the
/// exception: it gets its own hosting controller and would need its own `.immersive()`. That is the
/// same trap Android hit, where each `Dialog` owns a `Window` and needs `ImmersiveWindow()`.
///
/// The home indicator is a hint, not a command: `persistentSystemOverlays(.hidden)` lets iOS fade the
/// pill after a moment of inactivity, which is as far as iOS goes — there is no equivalent of hiding
/// Android's navigation bar outright.
extension View {
    func immersive() -> some View {
        statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
    }
}
