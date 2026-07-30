# iOS Navigation Drawer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the iOS app the navigation drawer the Android app has, so Bands / Songs / Rehearsal / Storage / About / the two web properties / Logout are all reachable from one place — and so the nav bar is free for the songs control bars in the next spec.

**Architecture:** A new `AppShell` replaces `MainNavigation` and owns the navigation path plus the drawer's state. It renders a `ZStack` holding the `NavigationStack`, a tap-to-close scrim, and a panel translated in from `x: -width`. The panel is a *sibling* of the stack, not an overlay on a screen — that is what lets it cover the nav bar the way Android's `ModalNavigationDrawer` does. The path arithmetic lives in BandPilotKit so the replace-don't-push rule is covered by tests.

**Tech Stack:** SwiftUI (iOS 17), `@Observable`, BandPilotKit (a local Swift package, no third-party dependencies), XCTest.

**Spec:** `band-pilot-ios/docs/superpowers/specs/2026-07-30-ios-navigation-drawer-design.md`

## Global Constraints

- **Branch:** all work lands on `feature/ios-navigation-drawer`, already checked out.
- **Terminal builds and tests need `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`** prefixed. `xcode-select` on this machine points at CommandLineTools, which has no XCTest. This is a toolchain fact, never a code problem.
- **Never read a piped build's exit code.** `xcodebuild … | tail` reports `0` even when the build failed. Confirm success by grepping for the literal string `** BUILD SUCCEEDED **` / `** TEST SUCCEEDED **`.
- **New files need no `project.pbxproj` edits.** The app target uses filesystem-synchronized groups. A new file inside `band-pilot-ios/` is picked up automatically.
- **Simulator:** iPhone 17, `id=5D8D1D4E-162C-46E3-95A9-380DF6CE58D2`, bundle `net.bandpilot`. Backend is local `:8080`; confirm with `curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/actuator/health` → `200`.
- **Autologin for headless runs:** `SIMCTL_CHILD_BP_AUTOLOGIN_EMAIL=john.doe@bandpilot.net SIMCTL_CHILD_BP_AUTOLOGIN_PASSWORD=bandpilot`. Demo band is id `1` ("Airdig").
- **Colours come from `Palette`** (`DesignSystem/Theme.swift`) only — never literal hex in a view. Panel `bgCard`, selected row `bgSoft`, selected content `selected`, unselected label `text`, unselected icon `textDim`, dividers `line`.
- **User-facing copy for About and the BandPilot Web dialog is copied verbatim from Android** (`roadie-android/.../ui/RoadieApp.kt`), including the device-dependent wording. Do not paraphrase — the point is that the two apps cannot drift.
- **Drawer opens by button only.** Do not add a left-edge drag gesture to open it; that edge is iOS's system back gesture.
- **No new dependencies.** No UI-test target.

---

## File Structure

**Created:**

| Path | Responsibility |
|---|---|
| `BandPilotKit/Sources/BandPilotKit/Logic/ShellRouting.swift` | `AppRoute` + the pure path arithmetic |
| `BandPilotKit/Tests/BandPilotKitTests/ShellRoutingTests.swift` | Its tests |
| `band-pilot-ios/Navigation/AppShell.swift` | `AppShell` view, `ShellState`, `ShellSheet`, scrim, animation, `.drawerToolbar(_:)` |
| `band-pilot-ios/Navigation/DrawerPanel.swift` | The panel's contents, top to bottom |
| `band-pilot-ios/Navigation/DrawerItem.swift` | One row + the dim hint line under a row |
| `band-pilot-ios/DesignSystem/Wordmark.swift` | `BandPilotWordmark` |
| `band-pilot-ios/Views/AboutSheet.swift` | About |
| `band-pilot-ios/Views/ManagementSiteSheet.swift` | The BandPilot Web open-or-share choice |

**Modified:**

| Path | Change |
|---|---|
| `band-pilot-ios/Navigation/RootView.swift` | `MainNavigation` → `AppShell`; `.id(session.user?.id)` |
| `band-pilot-ios/Views/Bands/BandsView.swift` | Drop the person menu; hamburger; record the tapped band |
| `band-pilot-ios/Views/Songs/SongsView.swift` | Drop the calendar button; title `"Songs"`; hamburger |
| `band-pilot-ios/Views/Rehearsals/RehearsalView.swift` | Title `"Rehearsal"`; hamburger |
| `band-pilot-ios/DesignSystem/Components.swift` | Add `Avatar` |

**Deleted:** `band-pilot-ios/Navigation/AppRoute.swift` — `AppRoute` moves into BandPilotKit, without which `ShellRouting` cannot be tested.

---

### Task 1: `ShellRouting` in BandPilotKit

**Files:**
- Create: `BandPilotKit/Sources/BandPilotKit/Logic/ShellRouting.swift`
- Test: `BandPilotKit/Tests/BandPilotKitTests/ShellRoutingTests.swift`
- Delete: `band-pilot-ios/Navigation/AppRoute.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `public enum AppRoute: Hashable, Sendable { case songs(bandId: Int); case rehearsals(bandId: Int) }`; `ShellRouting.path(to: AppRoute?) -> [AppRoute]`; `ShellRouting.selected(in: [AppRoute]) -> AppRoute?`.

- [ ] **Step 1: Write the failing test**

Create `BandPilotKit/Tests/BandPilotKitTests/ShellRoutingTests.swift`:

```swift
import XCTest
@testable import BandPilotKit

final class ShellRoutingTests: XCTestCase {
    func testBandsIsTheEmptyPath() {
        XCTAssertEqual(ShellRouting.path(to: nil), [])
    }

    func testEachDestinationReplacesTheWholePath() {
        XCTAssertEqual(ShellRouting.path(to: .songs(bandId: 7)), [.songs(bandId: 7)])
        XCTAssertEqual(ShellRouting.path(to: .rehearsals(bandId: 7)), [.rehearsals(bandId: 7)])
    }

    /// The reason this type exists at all. Walking Songs → Rehearsal → Songs from the drawer must
    /// leave one entry, not three: the back chevron has to keep meaning "Bands" however you got here.
    func testRepeatedDrawerNavigationNeverGrowsThePath() {
        var path = ShellRouting.path(to: .songs(bandId: 7))
        path = ShellRouting.path(to: .rehearsals(bandId: 7))
        path = ShellRouting.path(to: .songs(bandId: 7))
        XCTAssertEqual(path, [.songs(bandId: 7)])
    }

    func testSelectedIsNilAtTheRootAndTheLastRouteOtherwise() {
        XCTAssertNil(ShellRouting.selected(in: []))
        XCTAssertEqual(ShellRouting.selected(in: [.rehearsals(bandId: 3)]), .rehearsals(bandId: 3))
    }

    func testSwitchingBandKeepsThePathOneDeep() {
        XCTAssertEqual(ShellRouting.path(to: .songs(bandId: 9)), [.songs(bandId: 9)])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/rob/git/roadie/band-pilot-ios/BandPilotKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ShellRoutingTests
```

Expected: compile failure, `cannot find 'ShellRouting' in scope`.

- [ ] **Step 3: Write the implementation**

Create `BandPilotKit/Sources/BandPilotKit/Logic/ShellRouting.swift`:

```swift
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
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/rob/git/roadie/band-pilot-ios/BandPilotKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ShellRoutingTests
```

Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 5: Delete the app target's duplicate and confirm the whole suite still passes**

```bash
cd /Users/rob/git/roadie/band-pilot-ios
rm band-pilot-ios/Navigation/AppRoute.swift
cd BandPilotKit && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test 2>&1 | grep -E "Executed .* tests|error:"
```

Expected: `0 failures`, with exactly 5 more tests than the run before this change. Report the actual number rather than assuming it — the suite grows independently of this work.

- [ ] **Step 6: Build the app to confirm `AppRoute` resolves from the package**

`RootView.swift`, `BandsView.swift` and `SongsView.swift` all already `import BandPilotKit`, so deleting the local enum should need no other edit.

```bash
cd /Users/rob/git/roadie/band-pilot-ios
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project band-pilot-ios.xcodeproj \
  -scheme band-pilot-ios -configuration Debug \
  -destination 'id=5D8D1D4E-162C-46E3-95A9-380DF6CE58D2' -derivedDataPath build/dd build 2>&1 \
  | grep -E "error:|\*\* BUILD"
```

Expected: `** BUILD SUCCEEDED **` and no `error:` lines.

- [ ] **Step 7: Commit**

```bash
git add BandPilotKit/Sources/BandPilotKit/Logic/ShellRouting.swift \
        BandPilotKit/Tests/BandPilotKitTests/ShellRoutingTests.swift \
        band-pilot-ios/Navigation/AppRoute.swift
git commit -m "Move AppRoute into BandPilotKit behind a tested ShellRouting

The drawer navigates band pages by replacing the path rather than pushing onto it, so
the back chevron always means Bands. That rule now has tests instead of a comment."
```

---

### Task 2: `AppShell`, the drawer mechanics, and a minimal panel

The panel gets only Bands / Songs / Rehearsal / Logout here. Logout is included deliberately: `BandsView`'s person menu is removed in Task 5, and until the drawer can sign out there must be no window in which the app has no way to sign out at all.

**Files:**
- Create: `band-pilot-ios/Navigation/AppShell.swift`
- Create: `band-pilot-ios/Navigation/DrawerPanel.swift`
- Modify: `band-pilot-ios/Navigation/RootView.swift:44-87` (replace `MainNavigation`), `:13-21` (use `AppShell`)

**Interfaces:**
- Consumes: `AppRoute`, `ShellRouting` (Task 1).
- Produces:
  - `@Observable final class ShellState` with `var path: [AppRoute]`, `var isDrawerOpen: Bool`, `var currentBandId: Int?`, `var currentBandName: String?`, `var sheet: ShellSheet?`, `func open(_ route: AppRoute?)`, `func rememberBand(id: Int, name: String?)`, `var selected: AppRoute?`
  - `enum ShellSheet: String, Identifiable { case storage, about, managementSite }`
  - `struct AppShell: View` — `init(session: SessionStore, api: APIClient, library: MediaLibrary)`
  - `extension View { func drawerToolbar(_ shell: ShellState) -> some View }`
  - `struct DrawerPanel: View` — `init(session: SessionStore, library: MediaLibrary, shell: ShellState)`

- [ ] **Step 1: Create `AppShell.swift`**

```swift
import SwiftUI
import BandPilotKit

/// Which modal the shell is showing. Presented from the shell rather than from the drawer panel:
/// the panel is offset off-screen when closed, and a presentation owned by an off-screen view is a
/// good way to acquire a bug that only reproduces after the drawer shuts.
enum ShellSheet: String, Identifiable {
    case storage, about, managementSite
    var id: String { rawValue }
}

/// Navigation state for the signed-in app — the counterpart of Android's `RoadieAppContent`.
@Observable
final class ShellState {
    var path: [AppRoute] = []
    var isDrawerOpen = false
    var sheet: ShellSheet?

    /// The last band opened. Kept after backing out to Bands, so the drawer's band section survives
    /// the trip — Android's "the last one opened".
    ///
    /// Deliberately **not** derived from `path`: an empty path means Bands, and the band section has
    /// to outlive that. Two sources for one value is how the section would end up flickering away on
    /// the way back to Bands.
    var currentBandId: Int?
    var currentBandName: String?

    func open(_ route: AppRoute?) {
        path = ShellRouting.path(to: route)
        isDrawerOpen = false
    }

    func rememberBand(id: Int, name: String?) {
        currentBandId = id
        currentBandName = name
    }

    var selected: AppRoute? { ShellRouting.selected(in: path) }
}

/// The signed-in app: a navigation stack with a drawer over it.
///
/// The panel is a sibling of the `NavigationStack` inside the `ZStack`, not an overlay inside a
/// screen — that is what lets it cover the nav bar, which is what Android's `ModalNavigationDrawer`
/// does. It is also an ordinary view rather than a modal presentation, so it inherits the root's
/// hidden status bar and needs no `.immersive()` of its own.
struct AppShell: View {
    let session: SessionStore
    let api: APIClient
    let library: MediaLibrary
    @State private var shell = ShellState()

    init(session: SessionStore, api: APIClient, library: MediaLibrary) {
        self.session = session
        self.api = api
        self.library = library
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let raw = env["BP_OPEN_BAND"], let id = Int(raw) {
            let state = ShellState()
            // A deep link knows the id but not the name, so the drawer's heading falls back to
            // "BAND" — exactly as Android does before its own band fetch lands.
            state.rememberBand(id: id, name: nil)
            state.path = ShellRouting.path(
                to: env["BP_OPEN_REHEARSALS"] == "1" ? .rehearsals(bandId: id) : .songs(bandId: id)
            )
            _shell = State(wrappedValue: state)
        }
        #endif
    }

    var body: some View {
        GeometryReader { proxy in
            let width = min(320, proxy.size.width - 56)
            ZStack(alignment: .leading) {
                NavigationStack(path: $shell.path) {
                    BandsView(session: session, api: api, library: library, shell: shell)
                        .navigationDestination(for: AppRoute.self) { route in
                            switch route {
                            case let .songs(bandId):
                                SongsView(
                                    bandId: bandId,
                                    currentUserId: session.user?.id ?? 0,
                                    api: api,
                                    library: library,
                                    shell: shell
                                )
                            case let .rehearsals(bandId):
                                RehearsalView(bandId: bandId, api: api, shell: shell)
                            }
                        }
                }
                .tint(Palette.selected)

                if shell.isDrawerOpen {
                    // A Button, not a bare tap gesture, so VoiceOver can reach the dismiss.
                    Button { shell.isDrawerOpen = false } label: {
                        Color.black.opacity(0.5).ignoresSafeArea()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close navigation")
                    .transition(.opacity)
                }

                DrawerPanel(session: session, library: library, shell: shell)
                    .frame(width: width)
                    .offset(x: shell.isDrawerOpen ? 0 : -width)
            }
            .animation(.easeOut(duration: 0.25), value: shell.isDrawerOpen)
        }
        .sheet(item: $shell.sheet) { sheet in
            switch sheet {
            case .storage:
                NavigationStack { MediaStorageView(library: library) }
            case .about:
                Text("About")     // Task 4
            case .managementSite:
                Text("BandPilot Web")     // Task 4
            }
        }
    }
}

extension View {
    /// The leading hamburger, defined once for every screen inside the shell.
    ///
    /// Tap only. On iOS the left screen edge is the system back gesture, so the drawer deliberately
    /// has no edge-swipe to open — and the back chevron stays where iOS users expect it, alongside
    /// this button.
    func drawerToolbar(_ shell: ShellState) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { shell.isDrawerOpen = true } label: {
                    Image(systemName: "line.3.horizontal")
                }
                .accessibilityLabel("Open navigation")
            }
        }
    }
}
```

- [ ] **Step 2: Create a minimal `DrawerPanel.swift`**

```swift
import SwiftUI
import BandPilotKit

/// The drawer's contents, top to bottom, mirroring Android's `ModalDrawerSheet`
/// (roadie-android/.../ui/RoadieApp.kt:223-395).
struct DrawerPanel: View {
    let session: SessionStore
    let library: MediaLibrary
    let shell: ShellState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BandPilot")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Palette.text)
                .padding(20)

            Button("Bands") { shell.open(nil) }
                .foregroundStyle(shell.selected == nil ? Palette.selected : Palette.text)
                .padding(.horizontal, 16).padding(.vertical, 12)

            if let bandId = shell.currentBandId {
                Button("Songs") { shell.open(.songs(bandId: bandId)) }
                    .foregroundStyle(Palette.text)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                Button("Rehearsal") { shell.open(.rehearsals(bandId: bandId)) }
                    .foregroundStyle(Palette.text)
                    .padding(.horizontal, 16).padding(.vertical, 12)
            }

            Spacer()

            Button("Logout") { session.signOut() }
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.bgCard)
        .ignoresSafeArea(edges: .vertical)
    }
}
```

- [ ] **Step 3: Rewire `RootView.swift`**

Replace the whole `MainNavigation` struct (currently `:44-87`) — it is superseded by `AppShell`. In `RootView.body`, change the authenticated branch:

```swift
            if session.isAuthenticated {
                AppShell(session: session, api: api, library: library)
                    // Android wraps its content in key(user.id) so a re-login cannot inherit the
                    // previous account's navigation state. Same guard, same reason.
                    .id(session.user?.id)
            } else {
```

- [ ] **Step 4: Add the hamburger and the `shell` parameter to the three screens**

Minimal edits only — the titles and the calendar button are Task 5.

In `BandsView.swift`: add `let shell: ShellState` as a stored property, take it in `init` (`init(session:api:library:shell:)`, assigning `self.shell = shell`), and add `.drawerToolbar(shell)` next to the existing `.toolbar { … }`.

In `SongsView.swift`: add `let shell: ShellState`, extend `init(bandId:currentUserId:api:library:shell:)`, add `.drawerToolbar(shell)`.

In `RehearsalView.swift`: add `let shell: ShellState`, extend `init(bandId:api:shell:)`, add `.drawerToolbar(shell)`.

- [ ] **Step 5: Build**

```bash
cd /Users/rob/git/roadie/band-pilot-ios
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project band-pilot-ios.xcodeproj \
  -scheme band-pilot-ios -configuration Debug \
  -destination 'id=5D8D1D4E-162C-46E3-95A9-380DF6CE58D2' -derivedDataPath build/dd build 2>&1 \
  | grep -E "error:|\*\* BUILD"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Run it and look at the drawer**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=5D8D1D4E-162C-46E3-95A9-380DF6CE58D2
SHOT=/tmp/drawer-task2.png
xcrun simctl install $SIM build/dd/Build/Products/Debug-iphonesimulator/band-pilot-ios.app
xcrun simctl terminate $SIM net.bandpilot 2>/dev/null
SIMCTL_CHILD_BP_AUTOLOGIN_EMAIL=john.doe@bandpilot.net \
SIMCTL_CHILD_BP_AUTOLOGIN_PASSWORD=bandpilot \
SIMCTL_CHILD_BP_OPEN_BAND=1 \
xcrun simctl launch $SIM net.bandpilot
sleep 10
xcrun simctl io $SIM screenshot $SHOT
```

Then open the drawer by tapping the hamburger in the simulator and screenshot again. **Look at both images.** Required observations:
- The hamburger appears at the top left of the Songs screen, alongside the back chevron.
- The panel covers the nav bar (the hamburger and title are behind it, not beside it).
- Songs and Rehearsal appear under Bands, because `BP_OPEN_BAND=1` set `currentBandId`.
- The status bar is still hidden with the drawer open.

- [ ] **Step 7: Verify the back-chevron invariant**

Tap `Rehearsal` in the drawer, then the back chevron. Expected: **Bands**, not Songs. Screenshot it. If it lands on Songs, `shell.open` is pushing rather than replacing — fix that before continuing, since every later task assumes it.

- [ ] **Step 8: Commit**

```bash
git add band-pilot-ios/Navigation/AppShell.swift band-pilot-ios/Navigation/DrawerPanel.swift \
        band-pilot-ios/Navigation/RootView.swift band-pilot-ios/Views/Bands/BandsView.swift \
        band-pilot-ios/Views/Songs/SongsView.swift band-pilot-ios/Views/Rehearsals/RehearsalView.swift
git commit -m "Add the app shell and the drawer's mechanics

AppShell replaces MainNavigation and owns the path plus the drawer. The panel is a
sibling of the NavigationStack so it covers the nav bar, as Android's does. Panel
contents are still a stub; a re-login no longer inherits the previous navigation state."
```

---

### Task 3: The real panel — rows, wordmark, avatar, band heading, links, Storage

**Files:**
- Create: `band-pilot-ios/Navigation/DrawerItem.swift`, `band-pilot-ios/DesignSystem/Wordmark.swift`
- Modify: `band-pilot-ios/Navigation/DrawerPanel.swift` (replace the stub body), `band-pilot-ios/DesignSystem/Components.swift` (add `Avatar`)

**Interfaces:**
- Consumes: `ShellState`, `ShellSheet` (Task 2); `Palette`, `Palette.wordmarkGradient` (existing, `DesignSystem/Theme.swift:38-40`); `MediaLibrary.usedBytes: Int64` (existing); `SessionStore.user: User?` with `firstName`, `lastName`, `email`, `fullName`.
- Produces: `DrawerItem`, `DrawerHint`, `BandPilotWordmark(size:suffix:)`, `Avatar(initials:size:)`.

- [ ] **Step 1: Create `Wordmark.swift`**

```swift
import SwiftUI

/// The BandPilot wordmark: white "Band" + the brand banner's blue gradient "Pilot", optionally
/// followed by a plain suffix so a drawer item can read "BandPilot Home".
///
/// Deliberately the system bold rather than the app's Bebas Neue. Bebas is a tall condensed display
/// face quite unlike the banner's rounded sans, so the system face is the closer match — the same
/// reasoning, and the same conclusion, as the Android app's copy of this.
struct BandPilotWordmark: View {
    var size: CGFloat = 28
    var suffix: String = ""

    var body: some View {
        HStack(spacing: 0) {
            Text("Band").foregroundStyle(Palette.text)
            Text("Pilot").foregroundStyle(Palette.wordmarkGradient)
            if !suffix.isEmpty { Text(" \(suffix)").foregroundStyle(Palette.text) }
        }
        .font(.system(size: size, weight: .bold))
    }
}
```

- [ ] **Step 2: Create `DrawerItem.swift`**

```swift
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
```

- [ ] **Step 3: Add `Avatar` to `Components.swift`**

Append:

```swift
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
```

- [ ] **Step 4: Replace `DrawerPanel`'s body with the real contents**

```swift
import SwiftUI
import BandPilotKit

/// The public product/documentation site (band-pilot-home). Reads fine on a phone, so it opens
/// straight away.
private let homeSiteURL = URL(string: "https://www.bandpilot.net/")!

/// The Vue admin UI (roadie-mgt-ui) — band management this app deliberately does not offer. Opens
/// behind a choice, because its ag-Grid songlist is unusable at phone width.
let managementSiteURL = URL(string: "https://app.bandpilot.net/")!

/// The drawer's contents, top to bottom, mirroring Android's `ModalDrawerSheet`
/// (roadie-android/.../ui/RoadieApp.kt:223-395).
struct DrawerPanel: View {
    let session: SessionStore
    let library: MediaLibrary
    let shell: ShellState
    @Environment(\.openURL) private var openURL
    @State private var usedMB: Int64 = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BandPilotWordmark(size: 28).padding(20)

                DrawerItem("Bands", systemImage: "music.mic", isSelected: shell.selected == nil) {
                    shell.open(nil)
                }

                if let bandId = shell.currentBandId {
                    divider
                    // The band's own name in place of a static "BAND" label; a deep link that has no
                    // name yet falls back to it rather than showing nothing.
                    Text(shell.currentBandName ?? "BAND")
                        .font(.bebas(24))
                        .foregroundStyle(Palette.selected)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                    DrawerItem(
                        "Songs",
                        systemImage: "star.fill",
                        isSelected: shell.selected == .songs(bandId: bandId)
                    ) { shell.open(.songs(bandId: bandId)) }
                    DrawerItem(
                        "Rehearsal",
                        systemImage: "calendar",
                        isSelected: shell.selected == .rehearsals(bandId: bandId)
                    ) { shell.open(.rehearsals(bandId: bandId)) }
                }

                divider

                DrawerItem(systemImage: "arrow.up.forward.square", badge: nil, action: {
                    shell.isDrawerOpen = false
                    openURL(homeSiteURL)
                }, label: { BandPilotWordmark(size: 17, suffix: "Home") })
                DrawerHint(text: "Product Page and Documentation")

                DrawerItem(systemImage: "arrow.up.forward.square", badge: nil, action: {
                    shell.isDrawerOpen = false
                    shell.sheet = .managementSite
                }, label: { BandPilotWordmark(size: 17, suffix: "Web") })
                DrawerHint(text: "Manage Band on a large screen")

                divider

                if let user = session.user {
                    HStack(spacing: 12) {
                        Avatar(initials: (user.firstName.prefix(1) + user.lastName.prefix(1)).uppercased())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.fullName).foregroundStyle(Palette.text)
                            Text(user.email).font(.footnote).foregroundStyle(Palette.textDim)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                // Downloads are durable by design, which makes the app's footprint ours to show
                // rather than hide.
                DrawerItem("Storage", systemImage: "arrow.down.circle", badge: "\(usedMB) MB") {
                    shell.isDrawerOpen = false
                    shell.sheet = .storage
                }
                DrawerItem("About", systemImage: "info.circle") {
                    shell.isDrawerOpen = false
                    shell.sheet = .about
                }
                DrawerItem("Logout", systemImage: "rectangle.portrait.and.arrow.right") {
                    session.signOut()
                }

                Spacer(minLength: 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.bgCard)
        .ignoresSafeArea(edges: .vertical)
        // Recomputed on open rather than continuously: the byte count is not an observable source.
        // Android reads it per recomposition of the drawer, which comes to the same thing.
        .onChange(of: shell.isDrawerOpen, initial: true) { _, isOpen in
            if isOpen { usedMB = library.usedBytes / 1_048_576 }
        }
        // A leftward drag closes the panel. Safe next to the system back gesture, which is a
        // rightward swipe starting at the screen edge and cannot begin on an open panel.
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.width < -40 { shell.isDrawerOpen = false }
                }
        )
    }

    private var divider: some View {
        Divider()
            .overlay(Palette.line)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
    }
}
```

- [ ] **Step 5: Build**

```bash
cd /Users/rob/git/roadie/band-pilot-ios
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project band-pilot-ios.xcodeproj \
  -scheme band-pilot-ios -configuration Debug \
  -destination 'id=5D8D1D4E-162C-46E3-95A9-380DF6CE58D2' -derivedDataPath build/dd build 2>&1 \
  | grep -E "error:|\*\* BUILD"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Screenshot the panel on both screens and look at them**

Install, launch with autologin **without** `BP_OPEN_BAND`, open the drawer, screenshot: expect wordmark, Bands (highlighted), **no** band section, the two site links with hints, the user row, Storage with a MB badge, About, Logout.

Then tap into Airdig, open the drawer, screenshot: expect the band section with `AIRDIG` in blue Bebas and Songs highlighted.

Required check: `Storage` shows a plausible MB figure, not `0 MB` when files are cached, and not a blank badge.

- [ ] **Step 7: Commit**

```bash
git add band-pilot-ios/Navigation/DrawerItem.swift band-pilot-ios/DesignSystem/Wordmark.swift \
        band-pilot-ios/DesignSystem/Components.swift band-pilot-ios/Navigation/DrawerPanel.swift
git commit -m "Fill in the drawer: rows, wordmark, band section, site links, Storage

Mirrors Android's ModalDrawerSheet. The band name comes from the tap rather than a fetch,
since SongsView owns its own view model and the shell cannot reach it."
```

---

### Task 4: About and the BandPilot Web choice

Android's `ManagementSiteChoiceDialog` is an `AlertDialog` with body text and two buttons. iOS gets a small sheet instead of a `confirmationDialog`, because `ShareLink` cannot be an action inside one — and a share sheet reached by a second tap through a plain alert is worse than a sheet that offers both directly.

**Files:**
- Create: `band-pilot-ios/Views/AboutSheet.swift`, `band-pilot-ios/Views/ManagementSiteSheet.swift`
- Modify: `band-pilot-ios/Navigation/AppShell.swift` (replace the two placeholder sheet cases)

**Interfaces:**
- Consumes: `BandPilotWordmark` (Task 3), `managementSiteURL` (Task 3), `Palette`, `\.isWide`.
- Produces: `AboutSheet()`, `ManagementSiteSheet()`.

- [ ] **Step 1: Create `AboutSheet.swift`**

Copy is verbatim from Android's `AboutDialog`.

```swift
import SwiftUI

/// Version, beta status, layout class and copyright — the counterpart of Android's `AboutDialog`.
///
/// Beta is called out next to the version and then explained, so the state of the app is visible
/// here permanently; the sign-in notice only appears once.
struct AboutSheet: View {
    @Environment(\.isWide) private var isWide
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        ZStack {
            Palette.bgCard.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 8) {
                BandPilotWordmark(size: 28).padding(.bottom, 4)
                Text("Version \(version) · Beta").foregroundStyle(Palette.text)
                Text(
                    "Still in beta and under active development — expect regular fixes, "
                        + "improvements and new features."
                )
                .font(.footnote)
                .foregroundStyle(Palette.textDim)
                Text("Layout: \(isWide ? "Tablet" : "Phone")").foregroundStyle(Palette.textDim)
                // The brand name rather than the author's own, and no legal-form suffix, since no
                // company is registered behind it yet. Copyright is unaffected by the label.
                Text("© 2026 Backline Software").foregroundStyle(Palette.textDim)

                Spacer()

                Button("OK") { dismiss() }
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(24)
        }
        .presentationDetents([.medium])
    }
}
```

- [ ] **Step 2: Create `ManagementSiteSheet.swift`**

Copy and the per-device emphasis are verbatim from Android's `ManagementSiteChoiceDialog`: both device classes get the same opening line, and only the phone is told to send the link somewhere bigger — that being the case where opening it here is the poor choice. On a tablet **Open** is the emphasised action; on a phone **Share** is.

```swift
import SwiftUI

/// Open BandPilot Web here, or share the link to open it somewhere bigger.
struct ManagementSiteSheet: View {
    @Environment(\.isWide) private var isWide
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Palette.bgCard.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                BandPilotWordmark(size: 24, suffix: "Web")
                Text(
                    "BandPilot Web is the place to manage all the details of your band — on a "
                        + (isWide
                            ? "large screen. A tablet works, but it's at its best on a PC."
                            : "large screen. A PC or tablet is strongly recommended; it doesn't "
                                + "work well on a phone.")
                )
                .foregroundStyle(Palette.textDim)
                if !isWide {
                    Text(
                        "You're on a phone, so consider sharing the link (email, WhatsApp, …) "
                            + "and opening it on a PC — or install BandPilot on a tablet and open "
                            + "it there."
                    )
                    .foregroundStyle(Palette.textDim)
                }

                Spacer()

                HStack(spacing: 20) {
                    Spacer()
                    if isWide {
                        ShareLink(item: managementSiteURL) { Text("Share") }
                            .foregroundStyle(Palette.textDim)
                        Button("Open") { dismiss(); openURL(managementSiteURL) }
                            .foregroundStyle(Palette.accent)
                            .fontWeight(.bold)
                    } else {
                        Button("Open") { dismiss(); openURL(managementSiteURL) }
                            .foregroundStyle(Palette.textDim)
                        ShareLink(item: managementSiteURL) { Text("Share") }
                            .foregroundStyle(Palette.accent)
                            .fontWeight(.bold)
                    }
                }
            }
            .padding(24)
        }
        .presentationDetents([.medium])
    }
}
```

- [ ] **Step 3: Wire the two sheets into `AppShell`**

Replace the placeholders in `AppShell.body`'s `.sheet(item:)`:

```swift
            case .about:
                AboutSheet()
            case .managementSite:
                ManagementSiteSheet()
```

- [ ] **Step 4: Build**

```bash
cd /Users/rob/git/roadie/band-pilot-ios
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project band-pilot-ios.xcodeproj \
  -scheme band-pilot-ios -configuration Debug \
  -destination 'id=5D8D1D4E-162C-46E3-95A9-380DF6CE58D2' -derivedDataPath build/dd build 2>&1 \
  | grep -E "error:|\*\* BUILD"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Screenshot both sheets**

Open the drawer → About → screenshot (expect the wordmark, a real version number rather than `?`, the beta line, `Layout: Phone`, the copyright). Then drawer → BandPilot Web → screenshot (expect both paragraphs, with **Share** as the emphasised action on a phone). Tap Share and confirm the system share sheet appears.

- [ ] **Step 6: Commit**

```bash
git add band-pilot-ios/Views/AboutSheet.swift band-pilot-ios/Views/ManagementSiteSheet.swift \
        band-pilot-ios/Navigation/AppShell.swift
git commit -m "Add About and the BandPilot Web open-or-share choice

Copy is verbatim from Android's AboutDialog and ManagementSiteChoiceDialog, including the
per-device emphasis. A sheet rather than a confirmationDialog, because ShareLink cannot be
an action inside one."
```

---

### Task 5: The nav-bar rework

**Files:**
- Modify: `band-pilot-ios/Views/Bands/BandsView.swift`, `band-pilot-ios/Views/Songs/SongsView.swift:23-34`, `band-pilot-ios/Views/Rehearsals/RehearsalView.swift:17`

**Interfaces:**
- Consumes: `ShellState.rememberBand(id:name:)`, `ShellState.open(_:)` (Task 2).
- Produces: nothing new.

- [ ] **Step 1: `BandsView` — drop the person menu, record the tapped band**

Remove the whole `.toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { … } } }` block, the `@State private var showStorage` property, and the `.navigationDestination(isPresented: $showStorage)` line. Storage and Sign out both live in the drawer now, and Android has no such menu.

Replace the `NavigationLink` in `content` with a button that records the band first — the name is in hand here, which is why the drawer needs no fetch of its own:

```swift
                    ForEach(vm.bands) { band in
                        Button {
                            shell.rememberBand(id: band.id, name: band.name)
                            shell.open(.songs(bandId: band.id))
                        } label: {
                            BandRow(band: band)
                        }
                        .buttonStyle(.plain)
                    }
```

- [ ] **Step 2: `SongsView` — drop the calendar button, title becomes "Songs"**

Change `.navigationTitle(vm.band?.name ?? "Songs")` to `.navigationTitle("Songs")`, and delete the calendar `ToolbarItem`:

```swift
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppRoute.rehearsals(bandId: vm.bandId)) {
                    Image(systemName: "calendar")
                }
            }
```

Rehearsal is reached from the drawer now, as on Android. Keep the count `ToolbarItem`.

- [ ] **Step 3: `RehearsalView` — title becomes "Rehearsal"**

Change `.navigationTitle("Rehearsals")` to `.navigationTitle("Rehearsal")`, matching Android's `Destination` label (singular).

- [ ] **Step 4: Build**

```bash
cd /Users/rob/git/roadie/band-pilot-ios
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project band-pilot-ios.xcodeproj \
  -scheme band-pilot-ios -configuration Debug \
  -destination 'id=5D8D1D4E-162C-46E3-95A9-380DF6CE58D2' -derivedDataPath build/dd build 2>&1 \
  | grep -E "error:|\*\* BUILD"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Screenshot the Songs nav bar**

Expect exactly: back chevron, hamburger, the title `Songs`, the song count. No band name, no calendar button. **Look at the screenshot** and confirm the band name is genuinely gone rather than truncated.

- [ ] **Step 6: Commit**

```bash
git add band-pilot-ios/Views/Bands/BandsView.swift band-pilot-ios/Views/Songs/SongsView.swift \
        band-pilot-ios/Views/Rehearsals/RehearsalView.swift
git commit -m "Free the nav bar: page-label titles, no calendar button, no person menu

The band name moves to the drawer's band section, where Android has it, and the calendar
button is replaced by the drawer's Rehearsal item. This is the space the songs control
bars need."
```

---

### Task 6: Verification pass

**Files:** none — this task only runs things and looks at the results.

**Interfaces:**
- Consumes: everything above.
- Produces: a pass/fail report against the spec's seven checks.

- [ ] **Step 1: Full unit suite**

```bash
cd /Users/rob/git/roadie/band-pilot-ios/BandPilotKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test 2>&1 | grep -E "Executed .* tests|error:|failed"
```

Expected: `0 failures`. Report the actual count.

- [ ] **Step 2: Clean build**

```bash
cd /Users/rob/git/roadie/band-pilot-ios
rm -rf build/dd
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project band-pilot-ios.xcodeproj \
  -scheme band-pilot-ios -configuration Debug \
  -destination 'id=5D8D1D4E-162C-46E3-95A9-380DF6CE58D2' -derivedDataPath build/dd build 2>&1 \
  | grep -E "error:|warning:|\*\* BUILD"
```

Expected: `** BUILD SUCCEEDED **`. Report any warnings rather than hiding them.

- [ ] **Step 3: Walk the spec's seven checks on the simulator, screenshotting each**

1. Drawer open on Bands — no band section.
2. Drawer open on Songs — band section present with the real band name, Songs highlighted.
3. Songs nav bar reads `Songs` with hamburger + count only.
4. Back chevron from Rehearsal lands on **Bands**, not Songs.
5. About sheet renders with a real version number.
6. BandPilot Web choice sheet, Share emphasised on a phone.
7. Status bar still hidden with the drawer open.

- [ ] **Step 4: Report honestly**

Write up what passed, what failed, and what was not checked. If a check failed, say so with the screenshot — do not describe the intended behaviour as though it were observed.

- [ ] **Step 5: Commit any fixes the pass produced**

If nothing needed fixing, skip. Do not create an empty commit.

---

## Deliberately not in this plan

- **The in-app Home button** at the foot of Android's drawer (`SystemNavButtons`). Android carries it only because it hides the system navigation bar; iOS's home swipe still works, so there is nothing to give back. Do not add it "for parity" — its absence *is* the parity.
- The five songs-screen control bars — the next spec. This plan only frees the nav bar for them.
- The **reload** button Android has and iOS lacks.
- Android's song-create and share-in features.
- The cache-budget divergence (Android 1 GB, iOS 2 GB in `MediaLibrary.defaultBudgetBytes`).
- Fixing the two stale passages in `roadie-android/CLAUDE.md` (`FlagVisibilityMenu`, practice-order sort) — the Android repo's business.
