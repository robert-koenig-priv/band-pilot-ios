# BandPilot iOS

SwiftUI iPhone/iPad client of the Roadie band-management system. Signed-in members browse their
bands, work the songlist (sort, group, filter, vote), run a rehearsal setlist, and play or read the
band's media — audio, YouTube, lead sheets.

The backend is `../roadie-service-main`; the sibling clients are `../roadie-android` (Kotlin/Compose)
and `../roadie-mgt-ui` (Vue admin UI).

- **App target:** `band-pilot-ios`, bundle id `net.bandpilot`, iOS 17.0+, iPhone + iPad.
- **All the logic lives in `BandPilotKit`**, a local Swift package referenced by the project. Models,
  networking, session, media and the view models are there, and so are all the tests — the app target
  holds only SwiftUI views, the design system and navigation. Nothing in the package imports SwiftUI,
  which is what lets the whole test suite run on macOS with no simulator.

## Layout

| path | what's in it |
|---|---|
| `band-pilot-ios/` | app target: `Views/`, `DesignSystem/`, `Navigation/`, `AppConfig.swift` |
| `BandPilotKit/Sources/BandPilotKit/` | `Models/`, `Networking/`, `Session/`, `Media/`, `ViewModels/`, `Logic/` |
| `BandPilotKit/Tests/BandPilotKitTests/` | the entire test suite |
| `Design/` | `ios-shots/` (current screens) and `reference/` (the look being matched) |
| `docs/superpowers/` | per-feature `specs/` and `plans/` |
| `Info.plist` | only the keys Xcode cannot express as `INFOPLIST_KEY_*` build settings |

## Build and run

In Xcode: open `band-pilot-ios.xcodeproj` and run the shared `band-pilot-ios` scheme. The package
resolves from disk — no network fetch, no `Package.resolved` to babysit.

From the command line:

```bash
xcodebuild -scheme band-pilot-ios \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Pick a destination that exists on the machine — `xcrun simctl list devices available`.

If a bare `xcodebuild`/`agvtool` answers *"requires Xcode, but active developer directory is
/Library/Developer/CommandLineTools"*, the shell is missing `DEVELOPER_DIR`:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

## Tests

```bash
cd BandPilotKit
swift test                                  # 112 tests, 2 skipped (the opt-in live ones)
swift test --filter PermissionsTests        # one suite
```

There is **no XCTest target in the Xcode project** — `swift test` is the whole suite, it runs on
macOS, and it needs no simulator and no running backend.

Coverage is deliberately narrow: the things that fail *quietly*. `Permissions` (role rules, mirrored
by hand into the Android and web clients so they cannot drift), `RatingMath` (must agree with the
server's average or a vote write patches the cache wrong), the media cache and downloader, header
panel algebra, song sorting/grouping, ISO-8601 decoding, and JSON decoding of every model.

### Live tests (opt-in, against a real backend)

`LiveAPITests` and `LiveRehearsalTests` skip unless `BP_LIVE=1`, so credentials never get committed.
They talk to `http://localhost:8080` and `LiveRehearsalTests` cleans up after itself (it creates a
throwaway rehearsal, adds and removes a song, then deletes it).

```bash
BP_LIVE=1 BP_EMAIL=you@example.com BP_PASSWORD=… swift test --filter LiveAPITests
```

## Pointing the app at a backend (the part that always bites)

`AppConfig.apiBaseURL` resolves once, in this order:

1. **`BP_API_BASE_URL`** in the launch environment — **DEBUG only**, and the switch for day-to-day
   work: tick/untick it in *Edit Scheme › Run › Arguments › Environment Variables*, no code change.
   The shared scheme deliberately ships **no** environment entries, so this is yours to add locally.
2. **`BPAPIBaseURL`** from `Info.plist`, if a build configuration supplies one. None does today.
3. Built-in default: **simulator → `http://localhost:8080`**, **device → the deployed backend** at
   `https://roadie-service-main.onrender.com`, because on a phone `localhost` is the phone itself.

On a real device against your Mac, use the Mac's Bonjour name, never `localhost`:

```
BP_API_BASE_URL = http://your-mac.local:8080
```

Plain HTTP to that host is permitted by the `NSAllowsLocalNetworking` exception in `Info.plist`
(which is also why that file exists at all). iOS will prompt once for local-network access;
`NSLocalNetworkUsageDescription` is the text it shows. Public HTTPS requirements are untouched.

A DEBUG build prints the resolved URL at launch:

```
[BandPilot] API base URL: http://localhost:8080
```

## Driving the app headlessly on the simulator

There is nothing to tap in a screenshot run, so DEBUG builds honour launch environment variables that
open a screen or a sheet directly. Set them in the scheme, or pass with `xcrun simctl launch`.

| variable | effect |
|---|---|
| `BP_AUTOLOGIN_EMAIL` / `BP_AUTOLOGIN_PASSWORD` | sign in without typing |
| `BP_OPEN_BAND=<id>` | open that band's Songs page |
| `BP_OPEN_REHEARSALS=1` | with `BP_OPEN_BAND`, open Rehearsals instead |
| `BP_OPEN_DRAWER=1` | start with the drawer open |
| `BP_OPEN_SHEET=storage\|about\|managementSite` | present that shell sheet |
| `BP_OPEN_PANELS=filter,sort,…` | pre-open songs header panels (`HeaderSection` raw values) |
| `BP_OPEN_VOTING` / `BP_OPEN_EDIT` | open a song's voting section / edit sheet |
| `BP_OPEN_MEDIA` / `BP_OPEN_MEDIA_SONG` / `BP_OPEN_PLAYER` | open the media panel / sheet / player |
| `BP_YT_TESTID` | force a known video id into the YouTube player |

## Bumping the version and the build number

Build number (`CURRENT_PROJECT_VERSION`, which Xcode injects as `CFBundleVersion`), from the
directory holding `band-pilot-ios.xcodeproj`:

```bash
agvtool next-version -all          # bump by one, all configurations
agvtool new-version -all 7         # set an exact build number
agvtool what-version               # read the current one
```

The **marketing version** (`MARKETING_VERSION` → `CFBundleShortVersionString`, currently `1.0`) is a
different story: ⚠️ **`agvtool new-marketing-version` does not work on this project.** It reports
success and changes nothing — it only knows how to write `CFBundleShortVersionString` into
`Info.plist`, which has no such key (and shouldn't), and it never touches the `MARKETING_VERSION`
build setting that actually feeds the bundle. `agvtool what-marketing-version` is equally unhelpful,
reporting `""`. Set it in Xcode instead — *target `band-pilot-ios` › General › Version* — which writes
`MARKETING_VERSION` in both configurations.

Three things about the build number in this project specifically:

- **`agvtool` needs `DEVELOPER_DIR`** (see *Build and run*) — otherwise the `/usr/bin/agvtool` shim
  resolves to the Command Line Tools and refuses. The tool is spelled a-g-v (Apple *Generic
  Versioning*), and it is **not** an `xcrun` utility, so `xcrun agvtool` fails even when the shim works.
- **Two lines of its output are noise here.** `Updated CFBundleVersion in ".../Info.plist"` did not
  happen: our `Info.plist` carries no `CFBundleVersion` key, and shouldn't —
  `GENERATE_INFOPLIST_FILE = YES` means Xcode writes it from `CURRENT_PROJECT_VERSION` at build time,
  and a hardcoded copy would be a second source of truth. `Cannot find ".../YES"` is an `agvtool`
  bug: it scans build settings for Info.plist paths and swallows the literal value of
  `GENERATE_INFOPLIST_FILE`. Both are safe to ignore.
- **Only `project.pbxproj` changes** — commit it, and check the diff shows the bump in **both** Debug
  and Release. That is what `-all` is for, and a version set in only one configuration is a TestFlight
  upload rejected an hour later.

## Offline media

Real bytes live in the band's own storage (S3-compatible bucket or Google Drive, configured by a band
admin in the web UI), never on the backend, which only mints short-lived presigned envelopes. Files
are cached under **Application Support** — not `Caches`, which iOS reclaims: "I pinned tonight's
setlist" must not mean "unless the OS needed the space on the train". The directory is excluded from
iCloud backup, and the app enforces its own **2 GB LRU budget**, honouring a `pinned` flag.

Cached files are named `<fileId>-<sha256 prefix>.<ext>` and nothing is renamed into place unverified,
so a corrupt index can cost metadata but never serve wrong bytes.

## Troubleshooting

- **"Data Backend currently not available"** — `APIError.backendWaking`. The deployed backend sleeps
  after ~15 minutes of idling and takes a moment to wake; the app retries. If it never clears, check
  the base URL the DEBUG log printed at launch.
- **Nothing loads on a physical device** — almost always the base URL: a device with no
  `BP_API_BASE_URL` goes to the deployed backend, not your Mac. See the section above.
- **"Your session expired. Please sign in again."** — any 401 clears the Keychain session and drops to
  the sign-in screen. The JWT has a 24-hour TTL and there is no refresh endpoint.
- **Signed up but can't sign in** — registration only emails a verification link; login is rejected
  (403) until it's opened. Running the backend locally, the link is printed to the `bootRun` log.
