# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Practical setup, commands and dev-loop knowledge live in `README.md` and are not repeated here. This
file is the *why*.

## Project overview

The SwiftUI iOS client of the Roadie/BandPilot band-management system (`../roadie-service-main` is the
backend and the source of truth for the API). Bundle id `net.bandpilot`, iOS 17+, iPhone and iPad from
one target.

**Deliberately limited scope**, matching the Android app: sign in/register, browse your bands, work a
band's songlist (sort/group/filter/search, inline voting, edit a song, flags), run a rehearsal
setlist, and play or read the band's media. It does **not** create or delete bands, edit band details,
delete songs, or manage the roster and memberships — those are admin-UI features.

### The split that matters most

`BandPilotKit` is a **local Swift package** holding models, networking, session, media and the view
models, plus every pure rule in `Logic/`. The app target holds only views, the design system and
navigation.

**Nothing in the package imports SwiftUI or UIKit** (enforceable by grep, and worth keeping that way).
That is what makes the whole suite run under `swift test` on macOS with no simulator, and it is the
reason `Logic/` exists as a directory: *a decision that only lives inside a SwiftUI view is a decision
nothing can check.* `ShellRouting` is the clearest example — the drawer's replace-don't-push rule is
three lines of arithmetic that could trivially have been inlined into `AppShell`, and then no test
could hold it.

When adding behaviour, ask which side of that line it belongs on before writing it. A pure rule with a
test beats a correct-looking view.

### Cross-client mirroring — these files must not drift

`Permissions.swift` and `RatingMath.swift` are **hand-mirrored** into `roadie-android`
(`data/Permissions.kt`, `averageRatingOf` in `Dtos.kt`) and the web UI. Keep the names identical so
the copies can be diffed by eye.

- `Permissions` — `isAdmin` (includes `.globalAdmin`), `canEditSongs` (ADMIN/EDITOR),
  `canUploadMedia`/`canDeleteMediaFile` (ADMIN/EDITOR/**MEMBER**, deliberately wider than song
  editing so a plain member can upload their own part — GUEST read-only), `canVoteFor` (self-only
  except ADMIN). There is deliberately **no per-file permission**: the owner tag is a UI filter, not
  an ACL. Deletes are soft and audited server-side, which is what makes that safe — not the client
  hiding a button.
- `RatingMath.averageRatingOf` must agree with the server's rule (1–5 stars, `0` = did not rate and is
  excluded, `-1` = veto and wins outright). `LiveAPITests` asserts exactly that against a real
  response, because the payoff for agreeing is patching a song's average locally after a vote write
  instead of re-fetching — and the failure mode is a number that is quietly wrong.

Where iOS **intentionally diverges** from Android, the divergence is documented at the site:
`HeaderSections` follows Android's stated toggle order rather than its actual panel order (the comment
there claims they match; they don't), and `SongSorting` has no status-rank "practice order" sort
because Android removed it.

## Architecture

- `Logic/` — the pure rules: `Permissions`, `RatingMath`, `HeaderSections` (the five songs-header
  panels; `allCases` order is both the toggle order and the stacking order), `SongSorting`,
  `SongGrouping`, `RehearsalScheduling` (the zoneless `plannedAt` string plus the default-selection
  heuristic), `ShellRouting`, `YouTube`.
- `Networking/` — `Endpoint<Response>` is a typed description of one call and **all path strings live
  in its route factories**, not at call sites. `APIClient` is one shared instance, attaches the bearer
  for `requiresAuth` calls and maps failures to `APIError`. `TokenProviding` is a protocol so the
  client and `SessionStore` don't form a reference cycle; it is main-actor isolated because the
  session is UI-observable state. `APIError.backendWaking` is its own case, and `userMessage` says
  "Data Backend currently not available" — the deployed backend sleeps after ~15 min, which is a
  *wait*, not a failure, and must not read like one.
- `Session/` — `SessionStore` (`@Observable`, main-actor) restores from the Keychain in `init` and
  **never leaves a half-restored session** (token without user → `signOut()`). `justSignedIn` is
  deliberately not persisted and not observed: restoring a Keychain session is not a sign-in, so the
  beta notice fires after signing in rather than on every cold start. `KeychainStore` uses
  `kSecAttrAccessibleAfterFirstUnlock` — the JWT belongs in the Keychain on iOS, where Android used
  SharedPreferences.
- `Models/` — mirror the backend JSON by name; no custom `CodingKeys` except for genuinely absent
  fields. Two traps already paid for: `ISO8601` exists because `ISO8601DateFormatter` **fails** on
  fractional seconds unless told to expect them and Jackson emits them (getting it wrong makes every
  envelope look expired, which reads as "the server is broken"), and formatters are cached because
  this runs per file. `MediaFileKind` carries an **`unknown(String)`** case so a kind added by a newer
  backend is displayed rather than silently dropped — whereas `MediaType` (media links) is a plain
  `String`-backed enum, where one unrecognised server value fails the *whole* list decode and renders an
  empty panel. `MediaFileKind`'s doc comment names that contrast deliberately; if media-link types ever
  start moving, `MediaType` should gain the same treatment.
- `Media/` — `MediaLibrary` is the app-wide façade (`MediaLibrary.live(api:)`, passed explicitly from
  `band_pilot_iosApp` like `api` and `session`). `MediaCache` lives in **Application Support**, not
  `Caches`: iOS reclaims `Caches`, and "I pinned tonight's setlist" cannot mean "unless the OS needed
  the space on the train" — the cost is that the 2 GB LRU budget is ours to enforce
  (`makeRoom(forIncoming:)`, pinned entries never evicted), and the directory is excluded from iCloud
  backup. **The filesystem is the source of truth**: `<fileId>-<sha256 prefix>.<ext>`, nothing renamed
  into place unverified, so a corrupt index costs metadata and never wrong bytes.
  `URLSessionFileTransfer` uses download/upload tasks with a per-task delegate and **not**
  `URLSession.bytes(for:)` — `AsyncBytes` iterates one `UInt8` through the async-sequence machinery
  and is a performance trap at 200 MB that reads like the modern choice. It applies the envelope's
  method, URL and headers **verbatim and branches on no provider**, so the session JWT can never leak
  to the band's bucket. `MediaUploads` stages the picked file into our own storage while hashing in
  one pass: the picker's URL is a short-lived security-scoped grant that a retry minutes later would
  find dead, and the staged copy *becomes* the cached file so an uploader never downloads their own
  file back.
- `ViewModels/` — `@Observable`, main-actor, no DI framework: they take `APIClient` and expose state
  plus banner-string errors.
- `band-pilot-ios/Navigation/` — `RootView` is the auth gate (`.id(session.user?.id)` so a re-login
  cannot inherit the previous account's navigation state — same guard and reason as Android's
  `key(user.id)`). `AppShell` + `ShellState` are the counterpart of Android's `RoadieAppContent`: a
  `NavigationStack` with the drawer as its **sibling in the `ZStack`**, which is what lets the panel
  cover the nav bar, and being an ordinary view rather than a presentation is what lets it inherit the
  hidden status bar. Sheets are presented from the **shell**, not from the drawer panel, which is
  offset off-screen when closed — a presentation owned by an off-screen view is a good way to acquire a
  bug that only reproduces after the drawer shuts. `ShellState.currentBandId` is deliberately **not**
  derived from `path`, since an empty path means Bands and the drawer's band section has to outlive
  that; two sources for one value is how that section ends up flickering.
- `band-pilot-ios/DesignSystem/` — the dark theme (`Palette`, plus a `Color(hexString:)` for the
  backend's flag colours), Bebas Neue for headings, `Wordmark` (white "Band" + gradient "Pilot") deliberately in the system bold rather than
  Bebas, because Bebas is a tall condensed face unlike the banner's rounded sans. `isWide` (regular
  horizontal size class, injected once at the root) is the app's one device-class check, mirroring
  Android's sw600dp: it sizes stars/icons up and shows chip text labels.
- **Immersive mode:** `.immersive()` is applied once at the root — status bar hidden, home indicator
  allowed to fade (`persistentSystemOverlays(.hidden)` is a hint, not a command). Parity with Android,
  and for the same reason: on stage the screen's job is the songlist or the lead sheet. ⚠️ This works
  because **every modal here is a page `sheet`**, which doesn't cover the full screen, so the root
  keeps owning the status-bar preference. A `fullScreenCover` gets its own hosting controller and would
  need its own `.immersive()` — the same trap Android hit, where each `Dialog` owns a `Window`. There
  is no `fullScreenCover` in the app today; if you add one, that's the cost.
- Media playback/viewing is where the platform frameworks appear, and only there: `AVFoundation`
  (`AudioPracticePlayer`), `WebKit` (`YouTubePlayer`), `PDFKit` (`MediaFileViewers`). Viewers route by
  **MIME type, not kind** — a photo of a chord chart is a `.sheet` with `image/jpeg`, and handing that
  to PDFKit draws a blank page.

## Commands

See `README.md` for the full dev loop. The short version:

- Tests: `cd BandPilotKit && swift test` (112 tests, 2 skipped — the opt-in live ones). No simulator,
  no backend needed. There is no XCTest target in the Xcode project.
- Build: `xcodebuild -scheme band-pilot-ios -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- Build number: `agvtool next-version -all` (its `Info.plist` and `YES` messages are noise — README
  explains). ⚠️ `agvtool new-marketing-version` silently does nothing here; `MARKETING_VERSION` is a
  build setting and must be changed in Xcode.
- Any of these needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` in a plain shell.

**DEBUG launch-env hooks exist so the app can be driven headlessly** (`BP_AUTOLOGIN_*`, `BP_OPEN_BAND`,
`BP_OPEN_PANELS`, `BP_OPEN_SHEET`, …; full table in README). Use them for screenshots and simulator
verification rather than adding temporary code — and keep new ones inside `#if DEBUG`.

## Toolchain notes

- `swift-tools-version: 6.0`, package platforms iOS 17 / macOS 14 (macOS is there so tests run on the
  host), **`swiftLanguageMode(.v5)`** on both targets, app target `SWIFT_VERSION = 5.0`. Concurrency is
  written to survive Swift 6 mode (actors, `Sendable`, main-actor isolation) but is not checked under
  it yet; flipping the mode is a deliberate, separate piece of work.
- Observation (`@Observable`) throughout, not `ObservableObject`/Combine.
- The package is referenced as an `XCLocalSwiftPackageReference` with `relativePath = BandPilotKit`, so
  it resolves from disk. There are no third-party dependencies **at all**, in either target — keep it
  that way unless something is genuinely unbuildable without one.
- `MARKETING_VERSION = 1.0`; `GENERATE_INFOPLIST_FILE = YES` *and* `INFOPLIST_FILE = Info.plist`
  together — Xcode merges the `INFOPLIST_KEY_*` settings into the hand-written file, so most keys
  belong in build settings and only the inexpressible ones in `Info.plist`.
- `VERSIONING_SYSTEM` is **not** set to `apple-generic`. `agvtool` bumps `CURRENT_PROJECT_VERSION`
  fine without it; it would only matter for a generated version `.c` file with
  `kBandPilotVersionString` symbols, which nothing reads.

## The Roadie system (sibling projects)

- `../roadie-service-main` — Kotlin/Spring Boot backend, **the source of truth for the API**. Local:
  `docker compose up -d` then `./gradlew bootRun` on :8080; deployed on Render (sleeps when idle).
  Stateless JWT, HS256, 24h TTL, no refresh endpoint — an expired token is a 401 and the app returns to
  sign-in.
- `../roadie-android` — Kotlin/Compose client. **Its `CLAUDE.md` is the fullest written account of the
  backend's domain model and REST surface**; read it rather than re-deriving, but verify against the
  backend before relying on a detail, since it is pinned to an older commit.
- `../roadie-mgt-ui` — Vue 3 admin SPA. `src/api.js` is the reference client for exact request/response
  shapes.
- `../band-pilot-home` — the public product site (bandpilot.net).

**Authorization is per band.** `band_membership` links a login to a roster entry and carries the
`SecurityRole` (`ADMIN`, `EDITOR`, `MEMBER`, `GUEST`), so one user holds different roles in different
bands. ⚠️ `GLOBAL_ADMIN` still exists in the enum but the backend retains it **only so existing
clients can deserialize the name** — it is no longer assignable or honoured, and server-wide admin is
the account-level `AppUser.globalAdmin` flag instead. `Permissions` accepts `.globalAdmin` as admin,
which is harmless and should stay until the enum value is actually removed.

### The routes this app calls

Auth: `POST api/auth/login`, `api/auth/register`, `api/auth/forgot-password`.
Bands: `GET api/bands`, `.../members` (own role + own `bandMemberId`), `.../band-members` (roster for
the voting section), `.../flags` (the catalog, read-only here).
Songs: **`GET api/bands/{id}/songs-with-ratings`** is the only song read — one bulk call carrying each
song's `averageRating`, `ratings` and `flags`; filtering, sorting and grouping then run locally on that
cache. Writes: `PUT .../songs/{id}`, `POST|PUT|DELETE .../songs/{songId}/ratings[/{id}]`,
`POST|DELETE .../songs/{songId}/flags[/{id}]`, `POST|PUT|DELETE .../songs/{songId}/media-links[/{id}]`.
Rehearsals: `GET|POST .../rehearsals`, `PUT|DELETE .../rehearsals/{id}`, `.../clone`,
`.../rehearsals/{id}/songs[/{rowId}]`, `.../missing-members[/{rowId}]`.
Media files: `.../media-files` (band-scoped with an optional song filter, **not** nested under a song —
a file need not belong to one, and one band-scoped read avoids the per-song fan-out that `mediaLinks`
still pays, which matters against a backend that sleeps), plus `upload-policy`, `upload-intents`,
`{id}/complete`, `{id}/download-url`.

Vote and flag writes **patch the local cache from the write response** and recompute the average with
`RatingMath` — no re-fetch. Media links are the one deliberate per-song fan-out, because the backend
has no bulk read for them.

## Docs

Per-feature specs and plans live in `docs/superpowers/specs/` and `docs/superpowers/plans/`
(`YYYY-MM-DD-<feature>.md`). They record the reasoning for a feature as it was built — the navigation
drawer and the songs control bars so far. Add to them rather than growing this file when the material
is feature-specific.
