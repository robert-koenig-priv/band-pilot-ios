# iOS navigation drawer — design

Date: 2026-07-30
Status: approved, not yet implemented
Scope: `band-pilot-ios` only. Android is the reference and is **not** modified.

## Why

The iOS app has no app-level navigation. Bands, Songs and Rehearsal are reached by pushing onto a
`NavigationStack`; Rehearsal only via a calendar button in the Songs toolbar; Storage and Sign out only
via a person-icon menu that exists on the Bands screen alone (`Views/Bands/BandsView.swift:28-32`).
There is no About screen and no link to either web property.

Android reaches all of it from one `ModalNavigationDrawer` (`roadie-android/.../ui/RoadieApp.kt:220-395`).
Porting that drawer is worth doing on its own merits, and it is also a prerequisite for the songs-screen
control bars (their own spec): those need five icon buttons in the nav bar, which only fits once the
band-name title and the calendar button move out — and the drawer is where they move to.

## Decisions taken before designing

Recorded because each closes off an alternative someone will otherwise re-propose:

1. **Two specs, drawer first.** The control bars are a separate, comparable body of work. This spec does
   not design them and must not constrain them beyond freeing the nav bar.
2. **The drawer opens by button only** — no left-edge swipe. On iOS the left edge belongs to the system
   back gesture; overriding it would make this app the only one on the device that behaves that way. The
   back chevron therefore stays on Songs and Rehearsal, alongside the hamburger.
3. **Band pages replace each other, they do not stack.** Mirrors Android's `popUpTo("bands")`, so the
   back chevron means "Bands" from either page, always.
4. **The nav-bar title becomes the page label** (`Bands` / `Songs` / `Rehearsal`), not the band name.
   Android's bar shows a page label too; the band name is what Android shows only in the drawer.
5. **The calendar button is removed** from the Songs toolbar. The drawer's Rehearsal item replaces it,
   as on Android.

## Architecture

`RootView`'s auth gate is unchanged. `MainNavigation` (`Navigation/RootView.swift:44-87`) is replaced by
`AppShell`, the counterpart of Android's `RoadieAppContent`: it owns the navigation path, the drawer's
open state, and which band the drawer offers pages for.

```
RootView (auth gate)
└── AppShell                    .id(session.user?.id)   ← mirrors Android's key(user.id)
    └── ZStack
        ├── NavigationStack(path: $shell.path)  { BandsView / SongsView / RehearsalView }
        ├── scrim   (opacity 0 → 0.5, tap = close)
        └── DrawerPanel          (offset -width → 0)
```

The panel is a **sibling of the `NavigationStack` inside the `ZStack`**, not an overlay on a screen. That
is what lets it cover the nav bar, which is what Android's `ModalNavigationDrawer` does.

### New files

| Path | Contents |
|---|---|
| `band-pilot-ios/Navigation/AppShell.swift` | `AppShell` view, `@Observable ShellState`, the `ZStack`, scrim, animation, the `.drawerToolbar(_:)` modifier |
| `band-pilot-ios/Navigation/DrawerPanel.swift` | The panel's contents, top to bottom |
| `band-pilot-ios/Navigation/DrawerItem.swift` | One row: icon + label + optional badge, selected/unselected styling |
| `band-pilot-ios/Views/AboutSheet.swift` | New — the app has no About today |
| `band-pilot-ios/DesignSystem/Wordmark.swift` | `BandPilotWordmark`: white "Band" + blue-gradient "Pilot" |
| `BandPilotKit/Sources/BandPilotKit/Logic/ShellRouting.swift` | The pure path arithmetic |
| `BandPilotKit/Tests/BandPilotKitTests/ShellRoutingTests.swift` | Its tests |

### Modified files

| Path | Change |
|---|---|
| `Navigation/RootView.swift` | `MainNavigation` → `AppShell`; add `.id(session.user?.id)` |
| `Navigation/AppRoute.swift` | **Deleted.** `AppRoute` moves into BandPilotKit next to `ShellRouting`, which cannot be tested otherwise |
| `Views/Bands/BandsView.swift` | Remove the person-icon menu and its `showStorage` state; add `.drawerToolbar`; report the tapped band's id **and name** to the shell |
| `Views/Songs/SongsView.swift` | Remove the calendar toolbar button; title becomes `"Songs"`; add `.drawerToolbar` |
| `Views/Rehearsals/RehearsalView.swift` | Title becomes `"Rehearsal"`; add `.drawerToolbar` |

`MediaStorageView` is unchanged; it is simply reached from the drawer instead of from `BandsView`'s menu.

## Routing

`ShellRouting` lives in BandPilotKit and holds no SwiftUI. It exists as a separate unit purely so
decision 3 is covered by a test rather than by a comment.

```swift
public enum AppRoute: Hashable, Sendable {   // moved from the app target
    case songs(bandId: Int)
    case rehearsals(bandId: Int)
}

public enum ShellRouting {
    /// Drawer navigation replaces the stack rather than pushing onto it, so the back chevron
    /// always means "Bands". Mirrors Android's popUpTo("bands").
    public static func path(to route: AppRoute?) -> [AppRoute]

    /// Which drawer item is highlighted; nil path = Bands.
    public static func selected(in path: [AppRoute]) -> AppRoute?
}
```

Behaviour:

- `path(to: nil)` → `[]` (Bands)
- `path(to: .songs(7))` → `[.songs(7)]`
- `path(to: .rehearsals(7))` → `[.rehearsals(7)]`
- Navigating Songs → Rehearsal → Songs leaves the path exactly one element long, never three.

`ShellState` (app target, `@Observable`) holds:

```swift
var path: [AppRoute] = []
var isDrawerOpen = false
var currentBandId: Int?
var currentBandName: String?
```

`currentBandId`/`currentBandName` are set by `BandsView` when a band is tapped — the name is already in
hand there, so the drawer needs no fetch of its own. They are **kept** after backing out to Bands, which
is Android's "the last band opened". A `BP_OPEN_BAND` deep link sets the id with no name, and the heading
falls back to `"BAND"` exactly as Android does before its own fetch lands.

Deliberately **not** derived from `path`: an empty path means Bands, and the band section has to survive
that. Two sources for the same value is how the band section would end up flickering away on the way
back to Bands, so `ShellState` owns it outright and `ShellRouting` has no opinion on it.

The `BP_OPEN_BAND` / `BP_OPEN_REHEARSALS` DEBUG hooks move from `MainNavigation.init` to `AppShell.init`
unchanged, and additionally set `currentBandId`.

## Drawer contents

Top to bottom, mirroring `RoadieApp.kt:223-395`:

1. `BandPilotWordmark`, 20pt padding all round.
2. **Bands** — icon `music.mic` (Android: `ic_band`), selected when `path` is empty.
3. When `currentBandId != nil`: a divider, then the band name (or `"BAND"`) as a Bebas heading in
   `Palette.selected`, then **Songs** (`star.fill`) and **Rehearsal** (`calendar`).
4. Divider. **BandPilot Home** (`arrow.up.forward.square`) with the dim hint
   "Product Page and Documentation" — opens `https://www.bandpilot.net/` directly.
5. **BandPilot Web** (same icon) with the hint "Manage Band on a large screen" — opens a
   `confirmationDialog` offering "Open in Safari" (`openURL`) or a `ShareLink`, mirroring Android's
   `ManagementSiteChoiceDialog`. Target `https://app.bandpilot.net/`.
6. Divider. The user row: `Avatar` with initials, full name, email.
7. **Storage** (`arrow.down.circle`) with a trailing `"<n> MB"` badge → pushes `MediaStorageView`.
8. **About** (`info.circle`) → presents `AboutSheet`.
9. **Logout** (`rectangle.portrait.and.arrow.right`) → `session.signOut()`, which flips `RootView` back
   to `AuthView`.

Hint lines sit under the **label**, not the icon (Android inset `start = 56.dp`), so they align with the
text above them.

Styling, from `Palette`: panel background `bgCard`; selected row `bgSoft` container with `selected` icon
and label; unselected `text` label with `textDim` icon; dividers `line`.

### Three deliberate departures from Android

- **No in-app Home button.** Android carries one (`SystemNavButtons`) only because it hides the system
  navigation bar. iOS's home swipe still works — nothing was taken away, so nothing needs giving back.
- **The band name comes from the tap, not a fetch.** Android reads
  `bandViewModel(currentBandId).band?.name`. On iOS `SongsView` constructs its own
  `BandDetailViewModel` internally, so the shell cannot reach it; `BandsView` supplies the name instead.
- **`BandsView`'s person-icon menu is removed.** Its two items are both in the drawer, and Android has
  no such menu.

## Interaction

- The hamburger (`line.3.horizontal`) is added by one `.drawerToolbar(_:)` modifier used by all three
  screens, so it is defined once. Accessibility label "Open navigation".
- Closes on: scrim tap (the scrim is a `Button` so it is reachable by VoiceOver), any item tap, or a
  leftward drag on the panel. A drag on the panel cannot collide with the system back gesture, which is
  a rightward swipe starting at the screen edge.
- Animation: 0.25s ease-out on both the panel offset and the scrim opacity.
- Width `min(320, screenWidth - 56)`, leaving a strip of the page visible as Android's does.
- The panel ignores the vertical safe area, consistent with the app's immersive mode
  (`DesignSystem/SystemBars.swift`). It is an ordinary view inside the shell's `ZStack` rather than a
  modal presentation, so it inherits the root's hidden status bar and needs no `.immersive()` of its own.

## Data flow, state, errors

- **No persistence.** Android's `currentBandId` is `rememberSaveable` — process-scoped, not written to
  preferences — so plain state in `ShellState` is the faithful equivalent.
- **Storage badge** recomputes `library.usedBytes` when the drawer opens (`onChange(of: isDrawerOpen)`).
  The byte count is not an observable source; Android likewise reads it per recomposition.
- **No network calls anywhere in the drawer.** The only absent value is the band name, whose fallback is
  `"BAND"`.
- `openURL` failures are silent, as Android's `uriHandler` is.
- **About** reads `CFBundleShortVersionString` and `CFBundleVersion` from `Bundle.main`, shows the
  `· Beta` marker and its one-line explanation, a `Layout: Phone/Tablet` line from `isWide`, and the
  copyright under "Backline Software". Wording is copied verbatim from Android's `AboutDialog` so the two
  cannot drift.

## Testing

**Unit (`BandPilotKit`, run with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`):**

- `path(to:)` replaces rather than appends, for each destination.
- Songs → Rehearsal → Songs leaves a one-element path.
- `selected(in:)` returns `nil` for an empty path and the last route otherwise.

**Simulator verification** (iPhone 17, local backend, screenshots kept and looked at):

1. Drawer open on Bands — no band section.
2. Drawer open on Songs — band section present with the real band name, Songs highlighted.
3. Nav bar on Songs reads `Songs` with hamburger + count only; no calendar button, no band name.
4. Back chevron from Rehearsal lands on Bands, not Songs.
5. About sheet.
6. BandPilot Web choice dialog.
7. Status bar still hidden with the drawer open.

No UI tests — the project has none and this does not justify introducing the dependency.

## Implementation stages

1. `ShellRouting` + tests. `AppRoute` moves to BandPilotKit.
2. `AppShell` + `ShellState` + scrim/animation + `.drawerToolbar`, with a stub panel. `RootView` rewired,
   `.id(session.user?.id)` added. Verify navigation and the back-chevron invariant.
3. `DrawerItem`, `BandPilotWordmark`, and the real `DrawerPanel` down to Logout — but with About and the
   Web choice dialog stubbed.
4. `AboutSheet` and the `ManagementSiteChoiceDialog` equivalent.
5. Nav-bar rework on all three screens: titles, remove the calendar button, remove `BandsView`'s menu.
6. Simulator verification pass.

## Out of scope

Named so none of it is silently dropped or silently absorbed:

- The five songs-screen control bars — next spec.
- The nav-bar **reload** button Android has and iOS lacks — its own small parity item.
- Android's newer song-create and share-in features, which iOS does not have at all.
- The cache-budget divergence noticed in passing: Android 1 GB, iOS 2 GB
  (`MediaLibrary.defaultBudgetBytes`).
- `roadie-android/CLAUDE.md` is stale in two places found while reading it: it documents a
  `FlagVisibilityMenu` with per-flag-id visibility (replaced by a single global `FlagVisibility`
  boolean), and a practice-order default sort (`songComparator` has no status rank). Fixing that file is
  the Android repo's business, not this spec's.
