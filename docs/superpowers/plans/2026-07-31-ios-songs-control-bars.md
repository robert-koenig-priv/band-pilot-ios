# iOS Songs Control Bars Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the iOS songs screen Android's five header control bars — Details, Sort, Group, Filter, Search — with persisted preferences, grouping, and the vote-freeze.

**Architecture:** The pure arithmetic (comparators, group keys, group ordering, the panel-visibility algebra) lives in BandPilotKit with unit tests. The app target holds one `@Observable SongsHeaderState` owning all panel state plus a thin `SongPrefs` `UserDefaults` wrapper, and one file per panel under `Views/Songs/Header/`. Android's equivalents are `private` inside a 2,733-line composable with no tests; this port deliberately does better there rather than identically.

**Tech Stack:** SwiftUI (iOS 17), `@Observable`, BandPilotKit (local Swift package, no third-party deps), XCTest.

**Spec:** `docs/superpowers/specs/2026-07-31-ios-songs-control-bars-design.md`

## Global Constraints

- **Branch:** `feature/ios-songs-control-bars`, already checked out.
- **Terminal builds and tests need `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.** `xcode-select` points at CommandLineTools, which has no XCTest. Toolchain fact, never a code problem.
- **Never trust a piped build's exit code.** `xcodebuild … | tail` reports `0` on failure. Confirm by grepping for the literal `** BUILD SUCCEEDED **`.
- **New files need no `project.pbxproj` edits** — the app target uses filesystem-synchronized groups.
- **Simulator:** iPhone 17, `id=5D8D1D4E-162C-46E3-95A9-380DF6CE58D2`, bundle `net.bandpilot`. Backend local `:8080` (`curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/actuator/health` → `200`). Autologin: `SIMCTL_CHILD_BP_AUTOLOGIN_EMAIL=john.doe@bandpilot.net SIMCTL_CHILD_BP_AUTOLOGIN_PASSWORD=bandpilot`, demo band id `1`, 90 songs.
- **`simctl` cannot tap.** Reach UI states with DEBUG launch hooks in the existing `BP_OPEN_*` family. Task 5 adds `BP_OPEN_PANELS`.
- **Colours come from `Palette` only** — never literal hex in a view.
- **Chip pills never change background with selection.** Only content tint changes (`Palette.selected` active, `Palette.textDim` inactive). This is the Android look and the reason the existing `FilterSortBar` is deleted rather than reused.
- **Chip labels:** on a phone an icon-bearing chip shows the icon alone with the label as its accessibility label; when `isWide` it also shows the text. Chips with no icon (`BPM`, `00:00`, `Song`) always show their text.
- **Preference keys are exactly as specified.** Do not invent or rename keys.
- **No new dependencies. No UI-test target.**

---

## File Structure

**Created — BandPilotKit:**

| Path | Responsibility |
|---|---|
| `Sources/BandPilotKit/Logic/SongGrouping.swift` | `GroupBy`, `GroupRatingMode`, `SongGroup`, `flagsInUse`, `groupKeys`, `groupLabel`, `groupSongs` |
| `Sources/BandPilotKit/Logic/HeaderSections.swift` | `HeaderSection` + the open/close algebra and what each opening clears |
| `Tests/BandPilotKitTests/SongGroupingTests.swift` | Keys, ordering, labels |
| `Tests/BandPilotKitTests/HeaderSectionsTests.swift` | Exclusivity and clearing |

**Created — app target, `band-pilot-ios/Views/Songs/Header/`:**

| Path | Responsibility |
|---|---|
| `SongPrefs.swift` | Typed `UserDefaults` load/save per key |
| `SongsHeaderState.swift` | `@Observable`: all panel state, `reset()`, the derived list |
| `HeaderChip.swift` | The shared pill + `SectionGlyph` + the nav-bar toggle row |
| `FilterChips.swift` | Status + flag chips and the in-use-flag menu |
| `SortChips.swift` | Sort chips with the direction chevron |
| `GroupChips.swift` | Group criterion chips |
| `DetailChips.swift` | The eight detail chips |
| `SongSearchField.swift` | The search field |
| `SongsHeader.swift` | Stacks whichever panels are open |
| `GroupHeader.swift` | The collapsible group row |

**Modified:**

| Path | Change |
|---|---|
| `BandPilotKit/…/Logic/SongSorting.swift` | New sort model; `practiceOrder` deleted |
| `BandPilotKit/Tests/…/SongSortingTests.swift` | Rewritten |
| `BandPilotKit/…/ViewModels/BandDetailViewModel.swift` | `statusFilter`/`sort`/`visibleSongs` removed; a stale comment corrected |
| `band-pilot-ios/Views/Songs/SongsView.swift` | Hosts the header; nav-bar toggles + Reset; no title; `FilterSortBar` deleted |
| `band-pilot-ios/Views/Songs/SongRow.swift` | Every detail conditional; Key/BPM/Duration added |

---

### Task 1: The sort model

**Files:**
- Modify: `BandPilotKit/Sources/BandPilotKit/Logic/SongSorting.swift`
- Modify: `BandPilotKit/Tests/BandPilotKitTests/SongSortingTests.swift`
- Modify: `BandPilotKit/Sources/BandPilotKit/ViewModels/BandDetailViewModel.swift:54-60`
- Modify: `band-pilot-ios/Views/Songs/SongsView.swift:121-126`

**Interfaces:**
- Consumes: `Song`, `SongStatus`, `SongFlag`.
- Produces: `SongSort` (`.name`/`.artist`/`.rating`); `SongSorting.filtered(_:status:flagId:flags:search:)`; `SongSorting.sorted(_:by:descending:ratingOf:)`. `practiceOrder` and `visible(_:status:sort:)` no longer exist.

- [ ] **Step 1: Replace the test file**

```swift
import XCTest
@testable import BandPilotKit

final class SongSortingTests: XCTestCase {
    private func song(
        _ id: Int, _ name: String, _ artist: String?, _ status: SongStatus, _ avg: Double
    ) -> Song {
        Song(id: id, bandId: 1, name: name, artist: artist, status: status, averageRating: avg)
    }

    private func avg(_ s: Song) -> Double { s.averageRating }

    func testSortByNameCaseInsensitive() {
        let songs = [song(1, "banana", "x", .suggested, 0), song(2, "Apple", "x", .suggested, 0)]
        XCTAssertEqual(SongSorting.sorted(songs, by: .name, descending: false, ratingOf: avg).map(\.id), [2, 1])
    }

    func testSortByArtistThenName() {
        let songs = [
            song(1, "B", "Zed", .suggested, 0),
            song(2, "A", "Alpha", .suggested, 0),
            song(3, "C", "Alpha", .suggested, 0),
        ]
        XCTAssertEqual(
            SongSorting.sorted(songs, by: .artist, descending: false, ratingOf: avg).map(\.id),
            [2, 3, 1]
        )
    }

    /// Android's rating comparator is rating-descending with name as the tiebreak, and `descending`
    /// then reverses the whole thing. So the un-reversed order is highest-rated first.
    func testRatingSortIsHighestFirstWithNameTiebreak() {
        let songs = [
            song(1, "B", "x", .suggested, 4.0),
            song(2, "A", "x", .suggested, 4.0),
            song(3, "C", "x", .suggested, 5.0),
        ]
        XCTAssertEqual(
            SongSorting.sorted(songs, by: .rating, descending: false, ratingOf: avg).map(\.id),
            [3, 2, 1]
        )
    }

    func testDescendingReversesTheOrder() {
        let songs = [song(1, "A", "x", .suggested, 0), song(2, "B", "x", .suggested, 0)]
        XCTAssertEqual(
            SongSorting.sorted(songs, by: .name, descending: true, ratingOf: avg).map(\.id),
            [2, 1]
        )
    }

    /// The rating is injected because two different ratings are in play — the band average and the
    /// member's own vote — and the sort must follow whichever the Rating display chip is showing.
    func testSortUsesTheInjectedRating() {
        let songs = [song(1, "A", "x", .suggested, 1.0), song(2, "B", "x", .suggested, 5.0)]
        let inverted: (Song) -> Double = { 6 - $0.averageRating }
        XCTAssertEqual(
            SongSorting.sorted(songs, by: .rating, descending: false, ratingOf: inverted).map(\.id),
            [1, 2]
        )
    }

    func testFilterByStatus() {
        let songs = [song(1, "A", "x", .suggested, 0), song(2, "B", "x", .readyForStage, 0)]
        let only = SongSorting.filtered(songs, status: .readyForStage, flagId: nil, flags: [:], search: "")
        XCTAssertEqual(only.map(\.id), [2])
        XCTAssertEqual(
            SongSorting.filtered(songs, status: nil, flagId: nil, flags: [:], search: "").count, 2
        )
    }

    func testFilterByFlagId() {
        let songs = [song(1, "A", "x", .suggested, 0), song(2, "B", "x", .suggested, 0)]
        let flags: [Int: [SongFlag]] = [
            1: [SongFlag(id: 10, songId: 1, flagId: 7, meaning: "Solo", description: nil,
                         meaningDetails: nil, color: nil, flagColor: "#FF0000", bandMemberId: nil)]
        ]
        let only = SongSorting.filtered(songs, status: nil, flagId: 7, flags: flags, search: "")
        XCTAssertEqual(only.map(\.id), [1])
    }

    func testSearchMatchesNameOrArtistCaseInsensitively() {
        let songs = [song(1, "Africa", "Toto", .suggested, 0), song(2, "Bitch", "Meredith", .suggested, 0)]
        XCTAssertEqual(
            SongSorting.filtered(songs, status: nil, flagId: nil, flags: [:], search: "TOT").map(\.id),
            [1]
        )
        XCTAssertEqual(
            SongSorting.filtered(songs, status: nil, flagId: nil, flags: [:], search: "bit").map(\.id),
            [2]
        )
    }
}
```

`SongFlag` has no memberwise `init` today — it is decode-only. Add one to the struct in
`Models/Models.swift` so tests can build fixtures:

```swift
    public init(
        id: Int, songId: Int, flagId: Int, meaning: String, description: String?,
        meaningDetails: String?, color: String?, flagColor: String, bandMemberId: Int?
    ) {
        self.id = id; self.songId = songId; self.flagId = flagId; self.meaning = meaning
        self.description = description; self.meaningDetails = meaningDetails; self.color = color
        self.flagColor = flagColor; self.bandMemberId = bandMemberId
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/rob/git/roadie/band-pilot-ios/BandPilotKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SongSortingTests
```

Expected: compile failure — `sorted` has no `descending:` / `ratingOf:` parameters.

- [ ] **Step 3: Rewrite `SongSorting.swift`**

```swift
import Foundation

/// Matches the Android app's sort options exactly. There is no status-rank ("practice order") sort:
/// Android removed it, and `songComparator` there has no status term at all.
public enum SongSort: String, Sendable, CaseIterable {
    case name
    case artist
    case rating
}

/// Local filtering + sorting of the cached song list.
public enum SongSorting {
    /// Status, flag and search all narrow the list. Status and flag are mutually exclusive in the UI,
    /// but this function does not enforce that — it just applies whatever it is given.
    public static func filtered(
        _ songs: [Song],
        status: SongStatus?,
        flagId: Int?,
        flags: [Int: [SongFlag]],
        search: String
    ) -> [Song] {
        var out = songs
        if let status { out = out.filter { $0.status == status } }
        if let flagId {
            out = out.filter { song in (flags[song.id] ?? []).contains { $0.flagId == flagId } }
        }
        let needle = search.trimmingCharacters(in: .whitespaces)
        if !needle.isEmpty {
            out = out.filter { song in
                song.name.localizedCaseInsensitiveContains(needle)
                    || (song.artist ?? "").localizedCaseInsensitiveContains(needle)
            }
        }
        return out
    }

    /// `ratingOf` is injected because the caller decides which rating is in play: the band average, or
    /// the signed-in member's own vote when the Rating display chip says so.
    ///
    /// `.rating` is rating-descending with name as the tiebreak — so `descending: false` already means
    /// highest-first — and `descending` then reverses the result. That is Android's arrangement, odd as
    /// it reads, and diverging would make the same chip produce different orders on the two platforms.
    public static func sorted(
        _ songs: [Song],
        by sort: SongSort,
        descending: Bool,
        ratingOf: (Song) -> Double
    ) -> [Song] {
        let ordered: [Song]
        switch sort {
        case .name:
            ordered = songs.sorted { lower($0.name) < lower($1.name) }
        case .artist:
            ordered = songs.sorted { a, b in
                let (x, y) = (lower(a.artist ?? ""), lower(b.artist ?? ""))
                return x == y ? lower(a.name) < lower(b.name) : x < y
            }
        case .rating:
            ordered = songs.sorted { a, b in
                let (x, y) = (ratingOf(a), ratingOf(b))
                return x == y ? lower(a.name) < lower(b.name) : x > y
            }
        }
        return descending ? ordered.reversed() : ordered
    }

    private static func lower(_ s: String) -> String { s.lowercased() }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /Users/rob/git/roadie/band-pilot-ios/BandPilotKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SongSortingTests
```

Expected: `Executed 8 tests, with 0 failures`.

- [ ] **Step 5: Keep the app compiling**

In `BandDetailViewModel.swift`, delete `statusFilter`, `sort` and `visibleSongs` (`:54-60`) — the header
state owns them from Task 4 on. Also correct the now-wrong comment on `ownerFilter` (`:40-41`), which
says "consistent with this app's deliberate choice not to persist filter/sort state": the songs header
does persist now, so the sentence becomes "In-memory: this is a per-session view of one song's panel,
not a page-level preference."

In `SongsView.swift`, replace `vm.visibleSongs` with a local derived list and drop `FilterSortBar`'s
sort `Picker` binding, so the file builds until Task 5 replaces it wholesale:

```swift
    private var derivedSongs: [Song] {
        SongSorting.sorted(vm.songs, by: .rating, descending: false, ratingOf: \.averageRating)
    }
```

Replace every `vm.visibleSongs` with `derivedSongs`, and delete the `private struct FilterSortBar`
declaration together with the `FilterSortBar(vm: vm)` call.

- [ ] **Step 6: Build**

```bash
cd /Users/rob/git/roadie/band-pilot-ios
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project band-pilot-ios.xcodeproj \
  -scheme band-pilot-ios -configuration Debug \
  -destination 'id=5D8D1D4E-162C-46E3-95A9-380DF6CE58D2' -derivedDataPath build/dd build 2>&1 \
  | grep -E "error:|\*\* BUILD"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add BandPilotKit band-pilot-ios/Views/Songs/SongsView.swift
git commit -m "Adopt Android's sort model; drop practiceOrder

Name/Artist/Rating plus a direction flag, with the rating injected so the sort can follow
either the band average or the member's own vote. The old status-rank sort is gone: Android
has no such option."
```

---

### Task 2: `SongGrouping` in BandPilotKit

**Files:**
- Create: `BandPilotKit/Sources/BandPilotKit/Logic/SongGrouping.swift`
- Test: `BandPilotKit/Tests/BandPilotKitTests/SongGroupingTests.swift`

**Interfaces:**
- Consumes: `Song`, `SongFlag`, `Flag`, `SongStatus`.
- Produces: `GroupBy` (`.status`/`.artist`/`.decade`/`.rating`/`.flag`), `GroupRatingMode` (`.band`/`.own`), `SongGroup(key:label:songs:flag:)`, `SongGrouping.flagsInUse(_:)`, `.groupKeys(for:by:flags:flagOrder:rating:)`, `.groupLabel(for:by:flagsInUse:)`, `.groupSongs(_:by:flagsInUse:keysOf:)`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import BandPilotKit

final class SongGroupingTests: XCTestCase {
    private func song(
        _ id: Int, _ name: String, _ artist: String? = "x", _ year: String? = nil,
        _ status: SongStatus = .suggested, _ avg: Double = 0
    ) -> Song {
        Song(id: id, bandId: 1, name: name, artist: artist, year: year, status: status, averageRating: avg)
    }

    private func flag(_ id: Int, _ songId: Int, _ flagId: Int, _ meaning: String) -> SongFlag {
        SongFlag(id: id, songId: songId, flagId: flagId, meaning: meaning, description: nil,
                 meaningDetails: nil, color: nil, flagColor: "#FF0000", bandMemberId: nil)
    }

    // MARK: keys

    func testStatusKeyIsTheStatus() {
        XCTAssertEqual(
            SongGrouping.groupKeys(for: song(1, "A", "x", nil, .needPractice), by: .status,
                                   flags: [], flagOrder: [], rating: 0),
            ["NEED_PRACTICE"]
        )
    }

    func testArtistKeyTrimsAndFallsBackToUnknown() {
        XCTAssertEqual(
            SongGrouping.groupKeys(for: song(1, "A", "  Toto "), by: .artist, flags: [], flagOrder: [], rating: 0),
            ["Toto"]
        )
        XCTAssertEqual(
            SongGrouping.groupKeys(for: song(2, "B", "   "), by: .artist, flags: [], flagOrder: [], rating: 0),
            [SongGrouping.unknownArtistKey]
        )
        XCTAssertEqual(
            SongGrouping.groupKeys(for: song(3, "C", nil), by: .artist, flags: [], flagOrder: [], rating: 0),
            [SongGrouping.unknownArtistKey]
        )
    }

    func testDecadeKeyFloorsToTheDecade() {
        XCTAssertEqual(
            SongGrouping.groupKeys(for: song(1, "A", "x", "1987"), by: .decade, flags: [], flagOrder: [], rating: 0),
            ["1980"]
        )
        XCTAssertEqual(
            SongGrouping.groupKeys(for: song(2, "B", "x", nil), by: .decade, flags: [], flagOrder: [], rating: 0),
            [SongGrouping.unknownYearKey]
        )
        // A full ISO date must not be read as a year — the backend can answer "1989-06-01".
        XCTAssertEqual(
            SongGrouping.groupKeys(for: song(3, "C", "x", "1989-06-01"), by: .decade,
                                   flags: [], flagOrder: [], rating: 0),
            ["1980"]
        )
    }

    func testRatingKeyBuckets() {
        func key(_ rating: Double) -> String {
            SongGrouping.groupKeys(for: song(1, "A"), by: .rating, flags: [], flagOrder: [], rating: rating)[0]
        }
        XCTAssertEqual(key(-1), SongGrouping.vetoedKey)
        XCTAssertEqual(key(0), SongGrouping.unratedKey)
        XCTAssertEqual(key(4.4), "4")
        XCTAssertEqual(key(4.5), "5")
        XCTAssertEqual(key(5), "5")
    }

    func testFlagKeysAreMultiMembershipInCatalogOrder() {
        let songFlags = [flag(1, 1, 9, "Zed"), flag(2, 1, 3, "Alpha")]
        XCTAssertEqual(
            SongGrouping.groupKeys(for: song(1, "A"), by: .flag, flags: songFlags,
                                   flagOrder: [3, 9], rating: 0),
            ["3", "9"]
        )
    }

    /// Deliberate, and pinned so nobody "fixes" it: a song with no flag belongs to no group and
    /// therefore vanishes from the list while grouped by Flag. Android behaves the same way.
    func testSongWithNoFlagBelongsToNoGroup() {
        XCTAssertEqual(
            SongGrouping.groupKeys(for: song(1, "A"), by: .flag, flags: [], flagOrder: [3], rating: 0),
            []
        )
    }

    // MARK: ordering

    func testStatusGroupsUseThePracticeChipOrder() {
        let songs = [
            song(1, "A", "x", nil, .suggested), song(2, "B", "x", nil, .readyForStage),
            song(3, "C", "x", nil, .needPractice),
        ]
        let groups = SongGrouping.groupSongs(songs, by: .status, flagsInUse: []) {
            SongGrouping.groupKeys(for: $0, by: .status, flags: [], flagOrder: [], rating: 0)
        }
        XCTAssertEqual(groups.map(\.key), ["READY_FOR_STAGE", "NEED_PRACTICE", "SUGGESTED"])
    }

    func testArtistGroupsByCountDescendingThenAlphabetical() {
        let songs = [
            song(1, "A", "Solo"), song(2, "B", "Duo"), song(3, "C", "Duo"),
            song(4, "D", nil),
        ]
        let groups = SongGrouping.groupSongs(songs, by: .artist, flagsInUse: []) {
            SongGrouping.groupKeys(for: $0, by: .artist, flags: [], flagOrder: [], rating: 0)
        }
        XCTAssertEqual(groups.map(\.key), ["Duo", "Solo", SongGrouping.unknownArtistKey])
    }

    func testDecadeGroupsAscendingWithUnknownLast() {
        let songs = [song(1, "A", "x", "1995"), song(2, "B", "x", nil), song(3, "C", "x", "1980")]
        let groups = SongGrouping.groupSongs(songs, by: .decade, flagsInUse: []) {
            SongGrouping.groupKeys(for: $0, by: .decade, flags: [], flagOrder: [], rating: 0)
        }
        XCTAssertEqual(groups.map(\.key), ["1980", "1990", SongGrouping.unknownYearKey])
    }

    func testRatingGroupsRunFiveDownThenUnratedThenVetoed() {
        let ratings: [Int: Double] = [1: 5, 2: 0, 3: -1, 4: 3]
        let songs = [song(1, "A"), song(2, "B"), song(3, "C"), song(4, "D")]
        let groups = SongGrouping.groupSongs(songs, by: .rating, flagsInUse: []) {
            SongGrouping.groupKeys(for: $0, by: .rating, flags: [], flagOrder: [],
                                   rating: ratings[$0.id] ?? 0)
        }
        XCTAssertEqual(groups.map(\.key), ["5", "3", SongGrouping.unratedKey, SongGrouping.vetoedKey])
    }

    // MARK: labels

    func testLabels() {
        XCTAssertEqual(SongGrouping.groupLabel(for: "NEED_PRACTICE", by: .status, flagsInUse: []), "Need practice")
        XCTAssertEqual(SongGrouping.groupLabel(for: SongGrouping.unknownArtistKey, by: .artist, flagsInUse: []), "Unknown artist")
        XCTAssertEqual(SongGrouping.groupLabel(for: "1980", by: .decade, flagsInUse: []), "1980s")
        XCTAssertEqual(SongGrouping.groupLabel(for: SongGrouping.unknownYearKey, by: .decade, flagsInUse: []), "Unknown year")
        XCTAssertEqual(SongGrouping.groupLabel(for: "5", by: .rating, flagsInUse: []), "5 Stars")
        XCTAssertEqual(SongGrouping.groupLabel(for: "1", by: .rating, flagsInUse: []), "1 Star")
        XCTAssertEqual(SongGrouping.groupLabel(for: SongGrouping.unratedKey, by: .rating, flagsInUse: []), "Not rated")
        XCTAssertEqual(SongGrouping.groupLabel(for: SongGrouping.vetoedKey, by: .rating, flagsInUse: []), "Vetoed")
    }

    // MARK: flagsInUse

    func testFlagsInUseIsDedupedAndSortedByMeaning() {
        let flags: [Int: [SongFlag]] = [
            1: [flag(1, 1, 9, "Zed"), flag(2, 1, 3, "alpha")],
            2: [flag(3, 2, 9, "Zed")],
        ]
        XCTAssertEqual(SongGrouping.flagsInUse(flags).map(\.id), [3, 9])
        XCTAssertEqual(SongGrouping.flagsInUse(flags).map(\.meaning), ["alpha", "Zed"])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/rob/git/roadie/band-pilot-ios/BandPilotKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SongGroupingTests
```

Expected: `cannot find 'SongGrouping' in scope`.

- [ ] **Step 3: Write `SongGrouping.swift`**

```swift
import Foundation

/// How the songlist may be grouped. Order matches the Group panel's chip order.
public enum GroupBy: String, Sendable, CaseIterable {
    case status, artist, decade, rating, flag
}

/// Which rating the Rating grouping buckets by. Independent of the Rating *display* chip: grouping by
/// the band average while showing your own vote is a legitimate combination.
public enum GroupRatingMode: String, Sendable {
    case band, own
}

public struct SongGroup: Identifiable, Sendable {
    public let key: String
    public let label: String
    public let songs: [Song]
    /// Non-nil only for `.flag` grouping, so the header can draw the flag's colour dot.
    public let flag: Flag?

    public var id: String { key }
}

public enum SongGrouping {
    public static let unknownArtistKey = "unknown-artist"
    public static let unknownYearKey = "unknown-year"
    public static let unratedKey = "unrated"
    public static let vetoedKey = "vetoed"

    /// Every flag some song actually carries — deduped by flag id, sorted by meaning.
    ///
    /// Deliberately distinct from the band's full catalog, which also contains flags nothing has been
    /// tagged with yet: the Filter chip, the Details toggle and the Flag group order all want the
    /// in-use list, and offering an unused flag as a filter would produce an empty list.
    public static func flagsInUse(_ flags: [Int: [SongFlag]]) -> [Flag] {
        var byId: [Int: Flag] = [:]
        for songFlags in flags.values {
            for f in songFlags where byId[f.flagId] == nil {
                byId[f.flagId] = Flag(
                    id: f.flagId, bandId: 0, meaning: f.meaning,
                    description: f.description, color: f.flagColor
                )
            }
        }
        return byId.values.sorted { $0.meaning.lowercased() < $1.meaning.lowercased() }
    }

    /// A song's group keys. A **list**, because Flag grouping is multi-membership — and an *empty*
    /// list is meaningful: the song appears in no group at all. Only `.flag` can produce that.
    public static func groupKeys(
        for song: Song, by groupBy: GroupBy, flags: [SongFlag], flagOrder: [Int], rating: Double
    ) -> [String] {
        switch groupBy {
        case .status:
            return [song.status.rawValue]
        case .artist:
            let trimmed = (song.artist ?? "").trimmingCharacters(in: .whitespaces)
            return [trimmed.isEmpty ? unknownArtistKey : trimmed]
        case .decade:
            guard let year = leadingYear(song.year) else { return [unknownYearKey] }
            return [String((year / 10) * 10)]
        case .rating:
            if rating <= Double(RatingMath.vetoValue) { return [vetoedKey] }
            if rating <= 0 { return [unratedKey] }
            return [String(min(5, max(1, Int(rating.rounded()))))]
        case .flag:
            let assigned = Set(flags.map(\.flagId))
            return flagOrder.filter { assigned.contains($0) }.map(String.init)
        }
    }

    public static func groupLabel(for key: String, by groupBy: GroupBy, flagsInUse: [Flag]) -> String {
        switch groupBy {
        case .status:
            return SongStatus(rawValue: key)?.label ?? key
        case .artist:
            return key == unknownArtistKey ? "Unknown artist" : key
        case .decade:
            return key == unknownYearKey ? "Unknown year" : "\(key)s"
        case .rating:
            if key == vetoedKey { return "Vetoed" }
            if key == unratedKey { return "Not rated" }
            return key == "1" ? "1 Star" : "\(key) Stars"
        case .flag:
            return flagsInUse.first { String($0.id) == key }?.meaning ?? key
        }
    }

    /// Bucket, then order the buckets per criterion. `keysOf` is injected so the caller can supply the
    /// frozen keys a voting section needs (see the vote-freeze) instead of the live ones.
    public static func groupSongs(
        _ songs: [Song], by groupBy: GroupBy, flagsInUse: [Flag], keysOf: (Song) -> [String]
    ) -> [SongGroup] {
        var buckets: [String: [Song]] = [:]
        var order: [String] = []
        for song in songs {
            for key in keysOf(song) {
                if buckets[key] == nil { order.append(key) }
                buckets[key, default: []].append(song)
            }
        }

        let keys: [String]
        switch groupBy {
        case .status:
            let canonical = ["READY_FOR_STAGE", "NEED_PRACTICE", "SUGGESTED"]
            keys = canonical.filter { buckets[$0] != nil }
        case .rating:
            let canonical = ["5", "4", "3", "2", "1", unratedKey, vetoedKey]
            keys = canonical.filter { buckets[$0] != nil }
        case .flag:
            keys = flagsInUse.map { String($0.id) }.filter { buckets[$0] != nil }
        case .artist:
            keys = sortedWithUnknownLast(order, unknown: unknownArtistKey) { a, b in
                let (ca, cb) = (buckets[a]?.count ?? 0, buckets[b]?.count ?? 0)
                return ca == cb ? a.lowercased() < b.lowercased() : ca > cb
            }
        case .decade:
            keys = sortedWithUnknownLast(order, unknown: unknownYearKey) {
                (Int($0) ?? 0) < (Int($1) ?? 0)
            }
        }

        return keys.map { key in
            SongGroup(
                key: key,
                label: groupLabel(for: key, by: groupBy, flagsInUse: flagsInUse),
                songs: buckets[key] ?? [],
                flag: groupBy == .flag ? flagsInUse.first { String($0.id) == key } : nil
            )
        }
    }

    /// The year field is a display string and the backend may answer a full ISO date ("1989-06-01"),
    /// so only the leading digits are read. Storing the whole date is what silently breaks decades.
    private static func leadingYear(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let digits = raw.prefix { $0.isNumber }
        return digits.count == 4 ? Int(digits) : nil
    }

    private static func sortedWithUnknownLast(
        _ keys: [String], unknown: String, by areInOrder: (String, String) -> Bool
    ) -> [String] {
        let known = keys.filter { $0 != unknown }.sorted(by: areInOrder)
        return keys.contains(unknown) ? known + [unknown] : known
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /Users/rob/git/roadie/band-pilot-ios/BandPilotKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter SongGroupingTests
```

Expected: `Executed 13 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add BandPilotKit/Sources/BandPilotKit/Logic/SongGrouping.swift \
        BandPilotKit/Tests/BandPilotKitTests/SongGroupingTests.swift
git commit -m "Add SongGrouping to BandPilotKit, with tests

Five criteria, their group ordering and labels. Android's equivalents are private inside a
2733-line composable and untested; these are pure and covered, including the deliberate rule
that a song with no flag belongs to no group."
```

---

### Task 3: The panel-visibility algebra

**Files:**
- Create: `BandPilotKit/Sources/BandPilotKit/Logic/HeaderSections.swift`
- Test: `BandPilotKit/Tests/BandPilotKitTests/HeaderSectionsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `HeaderSection` (`.details`/`.sort`/`.group`/`.filter`/`.search`, `CaseIterable` in that order, with `label`); `HeaderSections.toggling(_:in:) -> Set<HeaderSection>`; `HeaderSections.clears(onOpening:) -> HeaderClears`; `struct HeaderClears { let attributeFilter: Bool; let grouping: Bool; let search: Bool }`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import BandPilotKit

final class HeaderSectionsTests: XCTestCase {
    func testEntryOrderIsTheToggleRowOrder() {
        XCTAssertEqual(HeaderSection.allCases, [.details, .sort, .group, .filter, .search])
    }

    func testDetailsAndSortCoexistWithAnything() {
        var open = HeaderSections.toggling(.details, in: [])
        open = HeaderSections.toggling(.sort, in: open)
        open = HeaderSections.toggling(.filter, in: open)
        XCTAssertEqual(open, [.details, .sort, .filter])
    }

    func testFilterGroupAndSearchAreMutuallyExclusive() {
        let afterFilter = HeaderSections.toggling(.filter, in: [.group, .details])
        XCTAssertEqual(afterFilter, [.filter, .details])

        let afterSearch = HeaderSections.toggling(.search, in: [.filter, .sort])
        XCTAssertEqual(afterSearch, [.search, .sort])

        let afterGroup = HeaderSections.toggling(.group, in: [.search])
        XCTAssertEqual(afterGroup, [.group])
    }

    func testTogglingAnOpenSectionClosesIt() {
        XCTAssertEqual(HeaderSections.toggling(.details, in: [.details, .sort]), [.sort])
    }

    func testOpeningGroupClearsFiltersAndSearch() {
        let c = HeaderSections.clears(onOpening: .group)
        XCTAssertTrue(c.attributeFilter)
        XCTAssertTrue(c.search)
        XCTAssertFalse(c.grouping)
    }

    func testOpeningFilterClearsGroupingAndSearch() {
        let c = HeaderSections.clears(onOpening: .filter)
        XCTAssertTrue(c.grouping)
        XCTAssertTrue(c.search)
        XCTAssertFalse(c.attributeFilter)
    }

    func testOpeningSearchClearsGroupingAndFilters() {
        let c = HeaderSections.clears(onOpening: .search)
        XCTAssertTrue(c.grouping)
        XCTAssertTrue(c.attributeFilter)
        XCTAssertFalse(c.search)
    }

    func testOpeningDetailsOrSortClearsNothing() {
        for section in [HeaderSection.details, .sort] {
            let c = HeaderSections.clears(onOpening: section)
            XCTAssertFalse(c.attributeFilter)
            XCTAssertFalse(c.grouping)
            XCTAssertFalse(c.search)
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/rob/git/roadie/band-pilot-ios/BandPilotKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter HeaderSectionsTests
```

Expected: `cannot find 'HeaderSection' in scope`.

- [ ] **Step 3: Write `HeaderSections.swift`**

```swift
import Foundation

/// The songs screen's five header panels. `allCases` order is the nav-bar toggle order **and** the
/// order the panels stack in.
///
/// Android orders its toggles this way but renders its panels Filter, Sort, Group, Details, Search,
/// with a comment claiming the two match. They do not; this follows the stated intent.
public enum HeaderSection: String, Sendable, CaseIterable {
    case details, sort, group, filter, search

    public var label: String {
        switch self {
        case .details: return "Details"
        case .sort: return "Sort"
        case .group: return "Group"
        case .filter: return "Filter"
        case .search: return "Search"
        }
    }
}

/// What opening a section clears. Filter, Group and Search are three ways of narrowing the same list,
/// so leaving a previous one applied underneath produces a list nobody asked for.
public struct HeaderClears: Sendable {
    public let attributeFilter: Bool
    public let grouping: Bool
    public let search: Bool
}

public enum HeaderSections {
    /// A three-way exclusive set: Filter, Group and Search close one another. Details and Sort are
    /// orthogonal and coexist with anything.
    private static let exclusive: Set<HeaderSection> = [.filter, .group, .search]

    public static func toggling(
        _ section: HeaderSection, in visible: Set<HeaderSection>
    ) -> Set<HeaderSection> {
        if visible.contains(section) { return visible.subtracting([section]) }
        let kept = exclusive.contains(section) ? visible.subtracting(exclusive) : visible
        return kept.union([section])
    }

    public static func clears(onOpening section: HeaderSection) -> HeaderClears {
        switch section {
        case .group:
            return HeaderClears(attributeFilter: true, grouping: false, search: true)
        case .filter:
            return HeaderClears(attributeFilter: false, grouping: true, search: true)
        case .search:
            return HeaderClears(attributeFilter: true, grouping: true, search: false)
        case .details, .sort:
            return HeaderClears(attributeFilter: false, grouping: false, search: false)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /Users/rob/git/roadie/band-pilot-ios/BandPilotKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter HeaderSectionsTests
```

Expected: `Executed 8 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add BandPilotKit/Sources/BandPilotKit/Logic/HeaderSections.swift \
        BandPilotKit/Tests/BandPilotKitTests/HeaderSectionsTests.swift
git commit -m "Add the header-panel visibility algebra, with tests

Filter/Group/Search are three-way exclusive and clear one another's state; Details and Sort
are orthogonal. The rule most likely to regress, so it lives in the package with tests."
```

---

### Task 4: `SongPrefs` and `SongsHeaderState`

**Files:**
- Create: `band-pilot-ios/Views/Songs/Header/SongPrefs.swift`
- Create: `band-pilot-ios/Views/Songs/Header/SongsHeaderState.swift`

**Interfaces:**
- Consumes: `HeaderSection`, `HeaderSections`, `GroupBy`, `GroupRatingMode`, `SongSort`, `SongSorting`, `SongGrouping`, `SongStatus`, `Song`, `SongFlag`, `Flag`, `RatingMath`.
- Produces:
  - `enum SongDetail: String, CaseIterable { case status, artist, key, bpm, duration, media }` with `label` and `chipText`
  - `enum RatingDisplay: String { case average, own, hidden }`
  - `@Observable final class SongsHeaderState` with: `visibleSections: Set<HeaderSection>`, `statusFilter: SongStatus?`, `flagFilter: Int?`, `sort: SongSort`, `sortDescending: Bool`, `groupBy: GroupBy?`, `groupRatingMode: GroupRatingMode`, `visibleDetails: Set<SongDetail>`, `ratingDisplay: RatingDisplay`, `flagsVisible: Bool`, `search: String`, `expandedGroups: Set<String>`
  - methods `toggle(_ section:)`, `selectStatus(_:)`, `selectFlag(_:)`, `selectSort(_:)`, `selectGroup(_:)`, `cycleGroupRating()`, `toggleDetail(_:)`, `cycleRatingDisplay()`, `toggleFlagsVisible()`, `ensureVisible(_:)`, `ensureRatingShown()`, `reset()`, `reconcile(flagsInUse:)`

- [ ] **Step 1: Write `SongPrefs.swift`**

```swift
import Foundation

/// The songs screen's persisted preferences.
///
/// App-global rather than per-band, matching Android's `SharedPreferences` scope: the way you like to
/// look at a songlist is a habit, not a property of one band.
///
/// Every read **fails closed** — an unrecognised stored value is dropped rather than guessed, so a
/// preference written by a newer build cannot put this one into a state it has no UI for.
enum SongPrefs {
    private static let defaults = UserDefaults.standard

    enum Key {
        static let statusFilter = "song-status-filter"
        static let flagFilter = "song-flag-filter"
        static let sortOrder = "song-sort-order"
        static let sortDescending = "song-sort-descending"
        static let headerSections = "song-header-sections"
        static let ratingDisplay = "song-rating-display"
        static let visibleDetails = "song-visible-details"
        static let flagsVisible = "song-flags-visible"
        static let groupBy = "song-group-by"
        static let groupRatingMode = "song-group-rating-mode"
    }

    // MARK: read

    static func status() -> SongStatus? {
        defaults.string(forKey: Key.statusFilter).flatMap(SongStatus.init(rawValue:))
    }

    /// 0 is the absent sentinel: `integer(forKey:)` cannot distinguish a missing key from a stored 0,
    /// and no flag has id 0.
    static func flag() -> Int? {
        let raw = defaults.integer(forKey: Key.flagFilter)
        return raw > 0 ? raw : nil
    }

    static func sort() -> SongSort {
        defaults.string(forKey: Key.sortOrder).flatMap(SongSort.init(rawValue:)) ?? .rating
    }

    static func sortDescending() -> Bool { defaults.bool(forKey: Key.sortDescending) }

    static func sections() -> Set<HeaderSection> {
        let raw = defaults.stringArray(forKey: Key.headerSections) ?? []
        return Set(raw.compactMap(HeaderSection.init(rawValue:)))
    }

    static func ratingDisplay() -> RatingDisplay {
        defaults.string(forKey: Key.ratingDisplay).flatMap(RatingDisplay.init(rawValue:)) ?? .average
    }

    static func details() -> Set<SongDetail> {
        guard let raw = defaults.stringArray(forKey: Key.visibleDetails) else {
            return [.status, .artist, .key, .media]
        }
        return Set(raw.compactMap(SongDetail.init(rawValue:)))
    }

    static func flagsVisible() -> Bool {
        defaults.object(forKey: Key.flagsVisible) as? Bool ?? true
    }

    static func groupBy() -> GroupBy? {
        defaults.string(forKey: Key.groupBy).flatMap(GroupBy.init(rawValue:))
    }

    static func groupRatingMode() -> GroupRatingMode {
        defaults.string(forKey: Key.groupRatingMode).flatMap(GroupRatingMode.init(rawValue:)) ?? .band
    }

    // MARK: write

    static func setStatus(_ v: SongStatus?) { set(v?.rawValue, Key.statusFilter) }
    static func setFlag(_ v: Int?) { set(v, Key.flagFilter) }
    static func setSort(_ v: SongSort) { defaults.set(v.rawValue, forKey: Key.sortOrder) }
    static func setSortDescending(_ v: Bool) { defaults.set(v, forKey: Key.sortDescending) }
    static func setSections(_ v: Set<HeaderSection>) {
        defaults.set(v.map(\.rawValue), forKey: Key.headerSections)
    }
    static func setRatingDisplay(_ v: RatingDisplay) {
        defaults.set(v.rawValue, forKey: Key.ratingDisplay)
    }
    static func setDetails(_ v: Set<SongDetail>) {
        defaults.set(v.map(\.rawValue), forKey: Key.visibleDetails)
    }
    static func setFlagsVisible(_ v: Bool) { defaults.set(v, forKey: Key.flagsVisible) }
    static func setGroupBy(_ v: GroupBy?) { set(v?.rawValue, Key.groupBy) }
    static func setGroupRatingMode(_ v: GroupRatingMode) {
        defaults.set(v.rawValue, forKey: Key.groupRatingMode)
    }

    private static func set(_ value: Any?, _ key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}
```

- [ ] **Step 2: Write `SongsHeaderState.swift`**

```swift
import Foundation
import Observation
import BandPilotKit

/// Which optional attributes and controls the song cards show.
enum SongDetail: String, CaseIterable {
    case status, artist, key, bpm, duration, media

    /// The tablet chip label and the accessibility label on a phone.
    var label: String {
        switch self {
        case .status: return "Status"
        case .artist: return "Artist"
        case .key: return "Key"
        case .bpm: return "BPM"
        case .duration: return "Duration"
        case .media: return "Play"
        }
    }

    /// What an icon-less chip prints instead of an icon.
    var chipText: String? {
        switch self {
        case .bpm: return "BPM"
        case .duration: return "00:00"
        default: return nil
        }
    }

    var systemImage: String? {
        switch self {
        case .status: return "checkmark.circle.fill"
        case .artist: return "music.mic"
        case .key: return "music.note"
        case .media: return "play.fill"
        case .bpm, .duration: return nil
        }
    }
}

/// Whose rating the cards show, and whether they show one at all.
enum RatingDisplay: String, CaseIterable {
    case average, own, hidden

    var systemImage: String {
        switch self {
        case .average: return "star.leadinghalf.filled"
        case .own: return "star.circle"
        case .hidden: return "star.slash"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .average: return "Rating: band average"
        case .own: return "Rating: own vote"
        case .hidden: return "Rating: hidden"
        }
    }
}

/// Everything the five header panels control, plus the derived song list.
///
/// Separate from `BandDetailViewModel` on purpose: that type owns API state and lives in the package,
/// and preferences backed by `UserDefaults` do not belong in either.
@MainActor
@Observable
final class SongsHeaderState {
    var visibleSections: Set<HeaderSection>
    var statusFilter: SongStatus?
    var flagFilter: Int?
    var sort: SongSort
    var sortDescending: Bool
    var groupBy: GroupBy?
    var groupRatingMode: GroupRatingMode
    var visibleDetails: Set<SongDetail>
    var ratingDisplay: RatingDisplay
    var flagsVisible: Bool

    /// Not persisted: a search is a momentary act, not a habit — and a persisted one would greet you
    /// with an inexplicably short list on the next launch.
    var search = ""

    /// Per group, not persisted, and every group starts collapsed.
    var expandedGroups: Set<String> = []

    /// Bumped whenever the list should jump back to the top.
    private(set) var scrollToTopTick = 0

    init() {
        visibleSections = SongPrefs.sections()
        statusFilter = SongPrefs.status()
        flagFilter = SongPrefs.flag()
        sort = SongPrefs.sort()
        sortDescending = SongPrefs.sortDescending()
        groupBy = SongPrefs.groupBy()
        groupRatingMode = SongPrefs.groupRatingMode()
        visibleDetails = SongPrefs.details()
        ratingDisplay = SongPrefs.ratingDisplay()
        flagsVisible = SongPrefs.flagsVisible()

        // Stored state from before the exclusivity rules existed, or from a build with different
        // options. Status beats flag; a filter beats a grouping.
        if statusFilter != nil, flagFilter != nil { setFlag(nil) }
        if groupBy != nil, statusFilter != nil || flagFilter != nil { setGroup(nil) }
    }

    // MARK: sections

    func toggle(_ section: HeaderSection) {
        let wasOpen = visibleSections.contains(section)
        visibleSections = HeaderSections.toggling(section, in: visibleSections)
        SongPrefs.setSections(visibleSections)
        guard !wasOpen else { return }

        let clears = HeaderSections.clears(onOpening: section)
        if clears.attributeFilter { setStatus(nil); setFlag(nil) }
        if clears.grouping { setGroup(nil) }
        if clears.search { search = "" }
        if section == .group { expandedGroups = [] }
        scrollToTopTick += 1
    }

    // MARK: filter

    /// Statuses and flags are one exclusive radio group, and tapping the active status clears it.
    func selectStatus(_ status: SongStatus) {
        setStatus(statusFilter == status ? nil : status)
        if statusFilter != nil { setFlag(nil) }
    }

    func selectFlag(_ flagId: Int) {
        setFlag(flagFilter == flagId ? nil : flagId)
        if flagFilter != nil { setStatus(nil) }
    }

    /// A stored flag id whose flag no longer exists would filter everything away with no chip to
    /// show why, so it is dropped once the catalog is known.
    func reconcile(flagsInUse: [Flag]) {
        if let id = flagFilter, !flagsInUse.contains(where: { $0.id == id }) { setFlag(nil) }
    }

    // MARK: sort

    func selectSort(_ option: SongSort) {
        if sort == option {
            sortDescending.toggle()
            SongPrefs.setSortDescending(sortDescending)
        } else {
            sort = option
            sortDescending = false
            SongPrefs.setSort(option)
            SongPrefs.setSortDescending(false)
        }
        switch option {
        case .artist: ensureVisible(.artist)
        case .rating: ensureRatingShown()
        case .name: break
        }
        scrollToTopTick += 1
    }

    // MARK: group

    func selectGroup(_ option: GroupBy) {
        setGroup(groupBy == option ? nil : option)
        if groupBy != nil {
            groupRatingMode = .band
            SongPrefs.setGroupRatingMode(.band)
        }
        switch option {
        case .status: ensureVisible(.status)
        case .artist: ensureVisible(.artist)
        default: break
        }
    }

    /// off → band → own → off.
    func cycleGroupRating() {
        if groupBy != .rating {
            setGroup(.rating)
            groupRatingMode = .band
        } else if groupRatingMode == .band {
            groupRatingMode = .own
        } else {
            setGroup(nil)
            groupRatingMode = .band
        }
        SongPrefs.setGroupRatingMode(groupRatingMode)
        ensureRatingShown()
    }

    // MARK: details

    func toggleDetail(_ detail: SongDetail) {
        if visibleDetails.contains(detail) {
            visibleDetails.remove(detail)
        } else {
            visibleDetails.insert(detail)
        }
        SongPrefs.setDetails(visibleDetails)
    }

    func cycleRatingDisplay() {
        let all = RatingDisplay.allCases
        let next = all[(all.firstIndex(of: ratingDisplay)! + 1) % all.count]
        ratingDisplay = next
        SongPrefs.setRatingDisplay(next)
    }

    func toggleFlagsVisible() {
        flagsVisible.toggle()
        SongPrefs.setFlagsVisible(flagsVisible)
    }

    /// Makes a detail visible, never hides one — so sorting or grouping by something cannot leave you
    /// looking at a list ordered by an invisible value.
    func ensureVisible(_ detail: SongDetail) {
        if !visibleDetails.contains(detail) { toggleDetail(detail) }
    }

    func ensureRatingShown() {
        if ratingDisplay == .hidden {
            ratingDisplay = .average
            SongPrefs.setRatingDisplay(.average)
        }
    }

    // MARK: reset

    /// Clears everything. Deliberately **not** "restore defaults": sort lands on `.name` although the
    /// default is `.rating`, and the rating and flag badges end up hidden rather than shown. Mirrors
    /// Android's reset, which is the behaviour a user pressing it twice would expect to be stable.
    func reset() {
        setStatus(nil)
        setFlag(nil)
        search = ""
        sort = .name
        sortDescending = false
        SongPrefs.setSort(.name)
        SongPrefs.setSortDescending(false)
        setGroup(nil)
        groupRatingMode = .band
        SongPrefs.setGroupRatingMode(.band)
        visibleDetails = []
        SongPrefs.setDetails([])
        ratingDisplay = .hidden
        SongPrefs.setRatingDisplay(.hidden)
        flagsVisible = false
        SongPrefs.setFlagsVisible(false)
        visibleSections = []
        SongPrefs.setSections([])
        expandedGroups = []
        scrollToTopTick += 1
    }

    // MARK: private setters that persist

    private func setStatus(_ v: SongStatus?) { statusFilter = v; SongPrefs.setStatus(v) }
    private func setFlag(_ v: Int?) { flagFilter = v; SongPrefs.setFlag(v) }
    private func setGroup(_ v: GroupBy?) { groupBy = v; SongPrefs.setGroupBy(v) }
}
```

- [ ] **Step 3: Build**

```bash
cd /Users/rob/git/roadie/band-pilot-ios
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project band-pilot-ios.xcodeproj \
  -scheme band-pilot-ios -configuration Debug \
  -destination 'id=5D8D1D4E-162C-46E3-95A9-380DF6CE58D2' -derivedDataPath build/dd build 2>&1 \
  | grep -E "error:|\*\* BUILD"
```

Expected: `** BUILD SUCCEEDED **`. Nothing consumes the new types yet — this step only proves they compile.

- [ ] **Step 4: Commit**

```bash
git add band-pilot-ios/Views/Songs/Header/
git commit -m "Add the songs header state and its persisted preferences

UserDefaults, app-global like Android's SharedPreferences, every read failing closed. Reset is
deliberately 'clear everything' rather than 'restore defaults', mirroring Android."
```

---

### Task 5: The nav-bar toggle row, the shared chip, and the derived list

**Files:**
- Create: `band-pilot-ios/Views/Songs/Header/HeaderChip.swift`
- Create: `band-pilot-ios/Views/Songs/Header/SongsHeader.swift`
- Modify: `band-pilot-ios/Views/Songs/SongsView.swift`
- Modify: `band-pilot-ios/Navigation/AppShell.swift` (the `BP_OPEN_PANELS` hook)

**Interfaces:**
- Consumes: `SongsHeaderState`, `HeaderSection`, `SongSorting`, `SongGrouping`, `Palette`, `\.isWide`.
- Produces: `HeaderChip`, `SectionGlyph`, `SongHeaderToggles`, `SongsHeader`, and on `SongsView` a `derivedSongs` computed property plus `ratingOf(_:)`.

- [ ] **Step 1: Write `HeaderChip.swift`**

```swift
import SwiftUI
import BandPilotKit

private let chipIconSize: CGFloat = 22

/// The shared header pill.
///
/// The pill's background **never changes with selection** — only the content's tint does. That is the
/// Android look, and it is why the old `FilterSortBar`, whose chips filled blue when active, is gone
/// rather than reused.
struct HeaderChip<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) { content() }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Palette.bgCard)
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Icon + optional text, tinted by selection — the body most chips want.
struct ChipLabel: View {
    let systemImage: String?
    let text: String
    let isSelected: Bool
    /// Overrides the selected tint. The Filter panel's flag chip uses the flag's own colour.
    var selectedTint: Color?
    @Environment(\.isWide) private var isWide

    private var tint: Color { isSelected ? (selectedTint ?? Palette.selected) : Palette.textDim }

    var body: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: chipIconSize * 0.8))
                .frame(height: chipIconSize)
                .foregroundStyle(tint)
                .accessibilityLabel(isWide ? "" : text)
            if isWide { Text(text).font(.footnote).foregroundStyle(tint) }
        } else {
            // No icon to shrink to, so the text always shows.
            Text(text).font(.footnote).foregroundStyle(tint)
        }
    }
}

/// The dim glyph that opens each panel row and closes that section when tapped.
///
/// Always `textDim`, never the accent: it identifies the row, it does not report a selection. No
/// leading padding — the Details row needs every point of width for its eight chips.
struct SectionGlyph: View {
    let section: HeaderSection
    let onClose: () -> Void

    var body: some View {
        Button(action: onClose) {
            Image(systemName: section.symbol)
                .font(.system(size: 16))
                .foregroundStyle(Palette.textDim)
                .padding(.vertical, 8)
                .padding(.trailing, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide \(section.label)")
    }
}

extension HeaderSection {
    var symbol: String {
        switch self {
        case .details: return "eye"
        case .sort: return "arrow.up.arrow.down"
        case .group: return "rectangle.stack"
        case .filter: return "line.3.horizontal.decrease"
        case .search: return "magnifyingglass"
        }
    }
}

/// One nav-bar toggle.
///
/// A single button rather than a view wrapping all five: a custom `View` containing a `ForEach` placed
/// in a `ToolbarItemGroup` can collapse into **one** toolbar item, which would silently give you one
/// icon where five belong. The `ForEach` therefore lives in the toolbar itself (see `SongsView`).
struct SongHeaderToggle: View {
    let section: HeaderSection
    let state: SongsHeaderState
    @Environment(\.isWide) private var isWide

    private var isOpen: Bool { state.visibleSections.contains(section) }

    var body: some View {
        Button { state.toggle(section) } label: {
            Image(systemName: section.symbol)
                .font(.system(size: isWide ? 26 : 20))
                .foregroundStyle(isOpen ? Palette.selected : Palette.textDim)
        }
        .accessibilityLabel((isOpen ? "Hide " : "Show ") + section.label)
    }
}
```

- [ ] **Step 2: Write `SongsHeader.swift` with only the rows that exist yet**

Panels arrive in Tasks 6–8; this is the container they slot into.

```swift
import SwiftUI
import BandPilotKit

/// Stacks whichever header panels are open, in `HeaderSection.allCases` order.
///
/// No card behind them: each chip carries its own pill, so a panel is just these rows on the page
/// background — as on Android.
struct SongsHeader: View {
    let state: SongsHeaderState
    let flagsInUse: [Flag]

    var body: some View {
        if !state.visibleSections.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(HeaderSection.allCases, id: \.self) { section in
                    if state.visibleSections.contains(section) { row(section) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder private func row(_ section: HeaderSection) -> some View {
        switch section {
        case .details, .sort, .group, .filter, .search:
            // Panels land in Tasks 6-8. Until then a section shows its glyph only, which still proves
            // the toggle row, the persistence and the exclusivity rules.
            HStack(spacing: 6) {
                SectionGlyph(section: section) { state.toggle(section) }
                Text(section.label).font(.footnote).foregroundStyle(Palette.textDim)
            }
        }
    }
}
```

- [ ] **Step 3: Rewire `SongsView`**

Add the state, drop the title, add the toolbar items, and derive the list. Replace the
`.navigationTitle`/`.toolbar` block and the `derivedSongs` stub from Task 1:

```swift
    @State private var header = SongsHeaderState()

    private var flagsInUse: [Flag] { SongGrouping.flagsInUse(vm.flags) }

    /// Which rating the cards and the sort follow — the band average, or this member's own vote.
    private func ratingOf(_ song: Song) -> Double {
        guard header.ratingDisplay == .own, let me = vm.myBandMemberId else { return song.averageRating }
        return Double(vm.individualRating(songId: song.id, memberId: me))
    }

    private var derivedSongs: [Song] {
        let filtered = SongSorting.filtered(
            vm.songs,
            status: header.statusFilter,
            flagId: header.flagFilter,
            flags: vm.flags,
            search: header.search
        )
        return SongSorting.sorted(
            filtered, by: header.sort, descending: header.sortDescending, ratingOf: ratingOf
        )
    }
```

Toolbar and title:

```swift
        // No title: back chevron + hamburger + count + Reset + five toggles already fill a 402pt bar.
        // The drawer's highlighted Songs item is what identifies the page.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(derivedSongs.count)").foregroundStyle(Palette.textDim)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { header.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                    .accessibilityLabel("Reset filters and options")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                // ForEach here, not inside a wrapper view: a custom View containing a ForEach can
                // collapse into a single toolbar item.
                ForEach(HeaderSection.allCases, id: \.self) { section in
                    SongHeaderToggle(section: section, state: header)
                }
            }
        }
```

Insert the header above the list, wrap the list in a `ScrollViewReader` so `scrollToTopTick` has an
effect, and reconcile a stale flag filter once the flags are known:

```swift
            VStack(spacing: 0) {
                SongsHeader(state: header, flagsInUse: flagsInUse)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // An invisible anchor at the very top. Scrolling to the first song instead
                            // would stop short whenever a group header sits above it.
                            Color.clear.frame(height: 0).id(topAnchorID)
                            …
                        }
                    }
                    // Opening a panel, changing the sort, or resetting all jump back to the top —
                    // otherwise you are left staring at row 40 of a list you just reordered.
                    .onChange(of: header.scrollToTopTick) { _, _ in
                        withAnimation { proxy.scrollTo(topAnchorID, anchor: .top) }
                    }
                }
            }
```

with `private let topAnchorID = "songs-top"` on `SongsView`.

```swift
        .onChange(of: flagsInUse.map(\.id)) { _, _ in header.reconcile(flagsInUse: flagsInUse) }
```

- [ ] **Step 4: Add the `BP_OPEN_PANELS` launch hook**

In `AppShell.init`'s `#if DEBUG` block, after the `BP_OPEN_SHEET` clause. `simctl` cannot tap, so panel
states are unreachable without it.

```swift
        // Comma-separated HeaderSection raw values, e.g. BP_OPEN_PANELS=filter,sort
        if let raw = env["BP_OPEN_PANELS"] {
            SongPrefs.setSections(
                Set(raw.split(separator: ",").compactMap { HeaderSection(rawValue: String($0)) })
            )
            seeded = true
        }
```

`SongsHeaderState` reads its sections from `SongPrefs` in `init`, so writing the preference before the
screen appears is enough — no extra plumbing.

- [ ] **Step 5: Build**

```bash
cd /Users/rob/git/roadie/band-pilot-ios
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project band-pilot-ios.xcodeproj \
  -scheme band-pilot-ios -configuration Debug \
  -destination 'id=5D8D1D4E-162C-46E3-95A9-380DF6CE58D2' -derivedDataPath build/dd build 2>&1 \
  | grep -E "error:|\*\* BUILD"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Check the nav bar actually fits — the measurement this plan gambled on**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=5D8D1D4E-162C-46E3-95A9-380DF6CE58D2
xcrun simctl install $SIM build/dd/Build/Products/Debug-iphonesimulator/band-pilot-ios.app
xcrun simctl terminate $SIM net.bandpilot 2>/dev/null
SIMCTL_CHILD_BP_AUTOLOGIN_EMAIL=john.doe@bandpilot.net \
SIMCTL_CHILD_BP_AUTOLOGIN_PASSWORD=bandpilot \
SIMCTL_CHILD_BP_OPEN_BAND=1 \
xcrun simctl launch $SIM net.bandpilot
sleep 11
xcrun simctl io $SIM screenshot /tmp/navbar.png
```

**Look at the screenshot.** Required: back chevron, hamburger, the count, the Reset arrow and **all five
toggle icons**, none clipped, nothing overlapping, no title. If items are missing or squeezed, stop and
report with the screenshot rather than shrinking icons on your own — the fallback is the toggles moving
to their own row, and that is the user's call.

- [ ] **Step 7: Verify a panel toggle persists across a relaunch**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=5D8D1D4E-162C-46E3-95A9-380DF6CE58D2
xcrun simctl terminate $SIM net.bandpilot 2>/dev/null
SIMCTL_CHILD_BP_AUTOLOGIN_EMAIL=john.doe@bandpilot.net \
SIMCTL_CHILD_BP_AUTOLOGIN_PASSWORD=bandpilot \
SIMCTL_CHILD_BP_OPEN_BAND=1 SIMCTL_CHILD_BP_OPEN_PANELS=filter,sort \
xcrun simctl launch $SIM net.bandpilot
sleep 11
xcrun simctl io $SIM screenshot /tmp/panels.png
# Relaunch with NO hook — the preference must still be there
xcrun simctl terminate $SIM net.bandpilot
SIMCTL_CHILD_BP_AUTOLOGIN_EMAIL=john.doe@bandpilot.net \
SIMCTL_CHILD_BP_AUTOLOGIN_PASSWORD=bandpilot \
SIMCTL_CHILD_BP_OPEN_BAND=1 \
xcrun simctl launch $SIM net.bandpilot
sleep 11
xcrun simctl io $SIM screenshot /tmp/panels-persisted.png
```

Both screenshots must show the Sort and Filter rows and their two toggles tinted blue. If the second is
bare, persistence is broken.

- [ ] **Step 8: Commit**

```bash
git add band-pilot-ios/Views/Songs/Header/HeaderChip.swift \
        band-pilot-ios/Views/Songs/Header/SongsHeader.swift \
        band-pilot-ios/Views/Songs/SongsView.swift band-pilot-ios/Navigation/AppShell.swift
git commit -m "Add the songs header toggle row, the shared chip, and the derived list

Five nav-bar toggles plus Reset, and the Songs title dropped to make room. The list is now
derived from the header state rather than the view model. Panels themselves land next.

BP_OPEN_PANELS joins the launch hooks, since simctl cannot tap."
```

---

### Task 6: Filter, Sort and Details panels, and the conditional row

**Files:**
- Create: `band-pilot-ios/Views/Songs/Header/FilterChips.swift`, `SortChips.swift`, `DetailChips.swift`
- Modify: `band-pilot-ios/Views/Songs/Header/SongsHeader.swift`, `band-pilot-ios/Views/Songs/SongRow.swift`

**Interfaces:**
- Consumes: `HeaderChip`, `ChipLabel`, `SectionGlyph`, `SongsHeaderState`, `SongDetail`, `RatingDisplay`, `flagsInUse`.
- Produces: `FilterChips`, `SortChips`, `DetailChips`; `SongRow` gains `state: SongsHeaderState`.

- [ ] **Step 1: Write `FilterChips.swift`**

```swift
import SwiftUI
import BandPilotKit

/// Status chips plus a flag chip. Statuses and flags are one exclusive radio group: picking either
/// clears the other, so the list is never narrowed two ways at once with only one chip to show it.
struct FilterChips: View {
    let state: SongsHeaderState
    let flagsInUse: [Flag]
    @Environment(\.isWide) private var isWide
    @State private var flagMenuOpen = false

    /// Chip order, matching Android's STATUS_CHIP_ORDER — not the enum's declaration order.
    private let order: [SongStatus] = [.readyForStage, .needPractice, .suggested]

    private var selectedFlag: Flag? { flagsInUse.first { $0.id == state.flagFilter } }

    var body: some View {
        HStack(spacing: 0) {
            SectionGlyph(section: .filter) { state.toggle(.filter) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(order, id: \.self) { status in
                        HeaderChip { state.selectStatus(status) } content: {
                            ChipLabel(
                                systemImage: symbol(status),
                                text: status.label,
                                isSelected: state.statusFilter == status
                            )
                        }
                    }
                    if !flagsInUse.isEmpty { flagChip }
                }
            }
        }
    }

    private var flagChip: some View {
        HeaderChip { flagMenuOpen = true } content: {
            ChipLabel(
                systemImage: "flag.fill",
                text: selectedFlag?.meaning ?? "Flags",
                isSelected: selectedFlag != nil,
                // The flag's own colour, not the accent — the badge on the card is that colour too.
                selectedTint: selectedFlag.map { Color(hexString: $0.color) }
            )
        }
        .popover(isPresented: $flagMenuOpen) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(flagsInUse) { flag in
                    Button { state.selectFlag(flag.id) } label: {
                        HStack(spacing: 10) {
                            Circle().fill(Color(hexString: flag.color)).frame(width: 14, height: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(flag.meaning)
                                    .fontWeight(.semibold)
                                    // The tinted name is the only selection cue — no checkmark, as Android.
                                    .foregroundStyle(
                                        state.flagFilter == flag.id ? Palette.selected : Palette.text
                                    )
                                if let d = flag.description, !d.isEmpty {
                                    Text(d).font(.caption).foregroundStyle(Palette.textDim)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minWidth: 240)
            .background(Palette.bgCard)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func symbol(_ status: SongStatus) -> String {
        switch status {
        case .readyForStage: return "checkmark.circle.fill"
        case .needPractice: return "wrench.and.screwdriver.fill"
        case .suggested: return "questionmark.circle"
        }
    }
}
```

- [ ] **Step 2: Write `SortChips.swift`**

```swift
import SwiftUI
import BandPilotKit

/// Sort chips. Tapping the **active** chip flips the direction instead of clearing the sort — a list
/// always has an order, so there is nothing to clear to.
struct SortChips: View {
    let state: SongsHeaderState

    private let order: [SongSort] = [.name, .artist, .rating]

    var body: some View {
        HStack(spacing: 0) {
            SectionGlyph(section: .sort) { state.toggle(.sort) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(order, id: \.self) { option in
                        let isSelected = state.sort == option
                        HeaderChip { state.selectSort(option) } content: {
                            ChipLabel(
                                systemImage: symbol(option),
                                text: label(option),
                                isSelected: isSelected
                            )
                            if isSelected {
                                Image(systemName: state.sortDescending ? "chevron.down" : "chevron.up")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Palette.selected)
                                    .accessibilityLabel(state.sortDescending ? "descending" : "ascending")
                            }
                        }
                    }
                }
            }
        }
    }

    private func label(_ option: SongSort) -> String {
        switch option {
        case .name: return "Song"
        case .artist: return "Artist"
        case .rating: return "Rating"
        }
    }

    /// Song has no icon, so its chip always shows the word — there is nothing to shrink to.
    private func symbol(_ option: SongSort) -> String? {
        switch option {
        case .name: return nil
        case .artist: return "music.mic"
        case .rating: return "star.fill"
        }
    }
}
```

- [ ] **Step 3: Write `DetailChips.swift`**

```swift
import SwiftUI
import BandPilotKit

/// Which optional attributes the cards show. Eight chips at a tighter 3pt spacing, so as many as
/// possible fit one phone width.
struct DetailChips: View {
    let state: SongsHeaderState
    let flagsInUse: [Flag]

    /// Hand-ordered, not `SongDetail.allCases`: Media leads, and the Flag and Rating chips are not
    /// `SongDetail` cases at all.
    private let order: [SongDetail] = [.media, .status, .artist, .key, .bpm, .duration]

    var body: some View {
        HStack(spacing: 0) {
            SectionGlyph(section: .details) { state.toggle(.details) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    if !flagsInUse.isEmpty { flagChip }
                    ForEach(Array(order.enumerated()), id: \.element) { index, detail in
                        // Rating sits after Media, matching Android's row.
                        if index == 1 { ratingChip }
                        HeaderChip { state.toggleDetail(detail) } content: {
                            ChipLabel(
                                systemImage: detail.systemImage,
                                text: detail.chipText ?? detail.label,
                                isSelected: state.visibleDetails.contains(detail)
                            )
                        }
                    }
                }
            }
        }
    }

    /// One boolean for every flag, not one per flag: Android tried per-flag switches and removed them.
    private var flagChip: some View {
        HeaderChip { state.toggleFlagsVisible() } content: {
            ChipLabel(systemImage: "flag.fill", text: "Flag", isSelected: state.flagsVisible)
        }
    }

    private var ratingChip: some View {
        HeaderChip { state.cycleRatingDisplay() } content: {
            ChipLabel(
                systemImage: state.ratingDisplay.systemImage,
                text: "Rating",
                isSelected: state.ratingDisplay != .hidden
            )
            .accessibilityLabel(state.ratingDisplay.accessibilityLabel)
        }
    }
}
```

- [ ] **Step 4: Wire the three rows into `SongsHeader.row(_:)`**

```swift
    @ViewBuilder private func row(_ section: HeaderSection) -> some View {
        switch section {
        case .details: DetailChips(state: state, flagsInUse: flagsInUse)
        case .sort: SortChips(state: state)
        case .filter: FilterChips(state: state, flagsInUse: flagsInUse)
        case .group, .search:
            // Tasks 7 and 8.
            HStack(spacing: 6) {
                SectionGlyph(section: section) { state.toggle(section) }
                Text(section.label).font(.footnote).foregroundStyle(Palette.textDim)
            }
        }
    }
```

- [ ] **Step 5: Make `SongRow` conditional and add Key / BPM / Duration**

`SongRow` gains `let state: SongsHeaderState` (passed from `SongsView`). Replace its `HStack` body:

```swift
            HStack(spacing: 10) {
                Button(action: onEdit) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.name)
                            .font(.system(size: 17))
                            .foregroundStyle(Palette.text)
                        if let second = secondLine {
                            Text(second).font(.subheadline).foregroundStyle(Palette.textDim)
                        }
                        if state.visibleDetails.contains(.key) || state.visibleDetails.contains(.bpm) {
                            Text(keyAndBpm).font(.caption).foregroundStyle(Palette.textDim)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if state.flagsVisible {
                    FlagBadges(flags: vm.flags[song.id] ?? [], size: isWide ? 16 : 14)
                }

                if state.visibleDetails.contains(.media), vm.hasMedia(song.id) {
                    Button(action: onMedia) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: isWide ? 24 : 20))
                            .foregroundStyle(Palette.selected)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onToggleVoting) {
                    HStack(spacing: 8) {
                        if state.visibleDetails.contains(.status) {
                            StatusMark(status: song.status, size: isWide ? 18 : 15)
                        }
                        if state.ratingDisplay != .hidden {
                            AverageRating(average: shownRating, size: isWide ? 20 : 16)
                        }
                        Image(systemName: isVotingOpen ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(Palette.textDim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
```

with these helpers on `SongRow`:

```swift
    /// Artist and duration share the second line, joined by " · " — as on Android.
    private var secondLine: String? {
        var parts: [String] = []
        if state.visibleDetails.contains(.artist), let a = song.artist, !a.isEmpty { parts.append(a) }
        if state.visibleDetails.contains(.duration), let secs = song.durationSec, secs > 0 {
            parts.append(DurationFormat.string(secs))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var keyAndBpm: String {
        var parts: [String] = []
        if state.visibleDetails.contains(.key), let k = song.key ?? song.originalKey, !k.isEmpty {
            parts.append(k)
        }
        if state.visibleDetails.contains(.bpm), let bpm = song.bpm ?? song.originalBpm, bpm > 0 {
            parts.append("\(bpm) BPM")
        }
        return parts.joined(separator: " · ")
    }

    /// Follows the Rating display chip: the band's average, or this member's own vote.
    private var shownRating: Double {
        guard state.ratingDisplay == .own, let me = vm.myBandMemberId else { return song.averageRating }
        return Double(vm.individualRating(songId: song.id, memberId: me))
    }
```

Pass `state: header` at the `SongRow(...)` call site in `SongsView`, and add one rule Android has for
the same reason — turning the Media detail off must not leave a media view up that its own affordance
can no longer reach:

```swift
        .onChange(of: header.visibleDetails.contains(.media)) { _, shown in
            if !shown { mediaSong = nil }
        }
```

- [ ] **Step 6: Build**

```bash
cd /Users/rob/git/roadie/band-pilot-ios
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project band-pilot-ios.xcodeproj \
  -scheme band-pilot-ios -configuration Debug \
  -destination 'id=5D8D1D4E-162C-46E3-95A9-380DF6CE58D2' -derivedDataPath build/dd build 2>&1 \
  | grep -E "error:|\*\* BUILD"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Screenshot the three panels**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=5D8D1D4E-162C-46E3-95A9-380DF6CE58D2
xcrun simctl install $SIM build/dd/Build/Products/Debug-iphonesimulator/band-pilot-ios.app
xcrun simctl terminate $SIM net.bandpilot 2>/dev/null
SIMCTL_CHILD_BP_AUTOLOGIN_EMAIL=john.doe@bandpilot.net \
SIMCTL_CHILD_BP_AUTOLOGIN_PASSWORD=bandpilot \
SIMCTL_CHILD_BP_OPEN_BAND=1 SIMCTL_CHILD_BP_OPEN_PANELS=details,sort,filter \
xcrun simctl launch $SIM net.bandpilot
sleep 11
xcrun simctl io $SIM screenshot /tmp/panels-3.png
```

**Look at it.** Required: three rows in the order Details, Sort, Filter, each starting with its dim
glyph; Details showing eight icon-only chips that fit the width; the active Sort chip carrying a
chevron; chips as grey pills whose *content* is tinted, never a filled blue pill. The cards must show
Key where a song has one, and no BPM or duration (both off by default).

- [ ] **Step 8: Commit**

```bash
git add band-pilot-ios/Views/Songs/Header/ band-pilot-ios/Views/Songs/SongRow.swift \
        band-pilot-ios/Views/Songs/SongsView.swift
git commit -m "Add the Filter, Sort and Details panels, and make the song row conditional

Every card detail is now gated by the Details panel, and Key/BPM/Duration are shown for the
first time on iOS. Chips are tint-only pills, as on Android."
```

---

### Task 7: Group panel, group headers, grouped rendering

**Files:**
- Create: `band-pilot-ios/Views/Songs/Header/GroupChips.swift`, `band-pilot-ios/Views/Songs/Header/GroupHeader.swift`
- Modify: `band-pilot-ios/Views/Songs/Header/SongsHeader.swift`, `band-pilot-ios/Views/Songs/SongsView.swift`

**Interfaces:**
- Consumes: `SongGrouping`, `GroupBy`, `GroupRatingMode`, `SongGroup`, `SongsHeaderState`.
- Produces: `GroupChips`, `GroupHeader`; `SongsView.groups` and `groupKeys(for:)`.

- [ ] **Step 1: Write `GroupChips.swift`**

```swift
import SwiftUI
import BandPilotKit

/// Group criterion chips. Single-select, and tapping the active chip clears grouping — unlike Sort,
/// "no grouping" is a real state.
struct GroupChips: View {
    let state: SongsHeaderState

    private let order: [GroupBy] = [.status, .artist, .decade, .rating, .flag]

    var body: some View {
        HStack(spacing: 0) {
            SectionGlyph(section: .group) { state.toggle(.group) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(order, id: \.self) { option in
                        let isSelected = state.groupBy == option
                        HeaderChip {
                            // Rating is a three-state cycle rather than a plain select.
                            option == .rating ? state.cycleGroupRating() : state.selectGroup(option)
                        } content: {
                            ChipLabel(
                                systemImage: symbol(option, isSelected: isSelected),
                                text: label(option, isSelected: isSelected),
                                isSelected: isSelected
                            )
                        }
                    }
                }
            }
        }
    }

    private func label(_ option: GroupBy, isSelected: Bool) -> String {
        switch option {
        case .status: return "Status"
        case .artist: return "Artist"
        case .decade: return "Decade"
        case .flag: return "Flag"
        case .rating:
            guard isSelected else { return "Rating" }
            return state.groupRatingMode == .band ? "Rating (Band)" : "Rating (Own)"
        }
    }

    private func symbol(_ option: GroupBy, isSelected: Bool) -> String {
        switch option {
        case .status: return "checkmark.circle.fill"
        case .artist: return "music.mic"
        case .decade: return "calendar"
        case .flag: return "flag.fill"
        case .rating:
            guard isSelected else { return "star.fill" }
            return state.groupRatingMode == .band ? "star.leadinghalf.filled" : "star.circle"
        }
    }
}
```

- [ ] **Step 2: Write `GroupHeader.swift`**

```swift
import SwiftUI
import BandPilotKit

/// One group's row in the songlist: a rotating chevron, an optional flag dot, the label, and the count.
///
/// A tinted row rather than indenting the songs beneath it — indentation costs width the song names
/// need.
struct GroupHeader: View {
    let group: SongGroup
    let collapsed: Bool
    let isWide: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.textDim)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                if let flag = group.flag {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(hexString: flag.color))
                }
                VStack(alignment: .leading, spacing: 2) {
                    if isWide, let d = group.flag?.description, !d.isEmpty {
                        HStack(spacing: 8) {
                            Text(group.label).font(.headline).foregroundStyle(Palette.text)
                            Text(d).font(.caption).foregroundStyle(Palette.textDim)
                        }
                    } else {
                        Text(group.label).font(.headline).foregroundStyle(Palette.text)
                        if let d = group.flag?.description, !d.isEmpty {
                            Text(d).font(.caption).foregroundStyle(Palette.textDim)
                        }
                    }
                }
                Spacer(minLength: 0)
                Text("\(group.songs.count)")
                    .font(.body.bold())
                    .foregroundStyle(Palette.selected)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(collapsed ? "Expand group" : "Collapse group")
    }
}
```

- [ ] **Step 3: Render groups in `SongsView`**

Add to `SongsView`:

```swift
    private func groupKeys(for song: Song) -> [String] {
        guard let groupBy = header.groupBy else { return [] }
        return SongGrouping.groupKeys(
            for: song, by: groupBy, flags: vm.flags[song.id] ?? [],
            flagOrder: flagsInUse.map(\.id), rating: groupRating(song)
        )
    }

    /// Grouping's rating is its own setting, independent of the Rating display chip.
    private func groupRating(_ song: Song) -> Double {
        guard header.groupRatingMode == .own, let me = vm.myBandMemberId else { return song.averageRating }
        return Double(vm.individualRating(songId: song.id, memberId: me))
    }

    private var groups: [SongGroup] {
        guard let groupBy = header.groupBy else { return [] }
        return SongGrouping.groupSongs(
            derivedSongs, by: groupBy, flagsInUse: flagsInUse, keysOf: groupKeys(for:)
        )
    }
```

and branch the list body:

```swift
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if header.groupBy == nil {
                            ForEach(derivedSongs) { song in songRow(song) }
                        } else {
                            ForEach(groups) { group in
                                GroupHeader(
                                    group: group,
                                    collapsed: !header.expandedGroups.contains(group.key),
                                    isWide: isWide
                                ) {
                                    if header.expandedGroups.contains(group.key) {
                                        header.expandedGroups.remove(group.key)
                                    } else {
                                        header.expandedGroups.insert(group.key)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 8)

                                if header.expandedGroups.contains(group.key) {
                                    // Keyed by group AND song id: Flag grouping is multi-membership,
                                    // so one song legitimately appears under several groups.
                                    ForEach(group.songs) { song in
                                        songRow(song).id("\(group.key):\(song.id)")
                                    }
                                }
                            }
                        }
                    }
                }
```

Extract the existing row construction into `@ViewBuilder private func songRow(_ song: Song) -> some View`
containing the current `SongRow(...)` plus its trailing `Divider()`, so both branches share it.

- [ ] **Step 4: Wire the Group row into `SongsHeader.row(_:)`**

```swift
        case .group: GroupChips(state: state)
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

- [ ] **Step 6: Screenshot a grouped list**

Launch with `SIMCTL_CHILD_BP_OPEN_PANELS=group` and `SIMCTL_CHILD_BP_OPEN_BAND=1`, screenshot, then tap
a criterion in the simulator and screenshot again.

**Look at both.** Required: the five group chips; after selecting one, every group **collapsed** with
its label and count, and expanding one revealing its songs. Selecting Status must also switch the
Status detail on, since `selectGroup` calls `ensureVisible(.status)`.

- [ ] **Step 7: Commit**

```bash
git add band-pilot-ios/Views/Songs/Header/GroupChips.swift \
        band-pilot-ios/Views/Songs/Header/GroupHeader.swift \
        band-pilot-ios/Views/Songs/Header/SongsHeader.swift band-pilot-ios/Views/Songs/SongsView.swift
git commit -m "Add the Group panel, group headers and grouped rendering

Five criteria with collapsible headers, all collapsed by default. Rows are keyed by group and
song id, because Flag grouping is multi-membership and one song can appear under several."
```

---

### Task 8: The Search panel

**Files:**
- Create: `band-pilot-ios/Views/Songs/Header/SongSearchField.swift`
- Modify: `band-pilot-ios/Views/Songs/Header/SongsHeader.swift`

**Interfaces:**
- Consumes: `SongsHeaderState`.
- Produces: `SongSearchField`.

- [ ] **Step 1: Write `SongSearchField.swift`**

```swift
import SwiftUI

/// The search field.
///
/// Hand-built rather than `.searchable`, which puts its field in the nav bar — already full — and
/// offers no way to make the leading magnifier close the section, which is how every other panel here
/// behaves.
struct SongSearchField: View {
    let state: SongsHeaderState
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // The magnifier is this panel's section glyph: tapping it closes the panel.
            Button { state.toggle(.search) } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.textDim)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide search")

            TextField("Song or artist…", text: Binding(
                get: { state.search },
                set: { state.search = $0 }
            ))
            .focused($focused)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .foregroundStyle(Palette.text)
            .tint(Palette.selected)

            if !state.search.isEmpty {
                Button { state.search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.textDim)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.bgSoft)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear { focused = true }
    }
}
```

- [ ] **Step 2: Wire it into `SongsHeader.row(_:)`, replacing the last placeholder**

```swift
        case .search: SongSearchField(state: state)
```

The `switch` now has a case per section and no placeholder branch.

- [ ] **Step 3: Build**

```bash
cd /Users/rob/git/roadie/band-pilot-ios
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project band-pilot-ios.xcodeproj \
  -scheme band-pilot-ios -configuration Debug \
  -destination 'id=5D8D1D4E-162C-46E3-95A9-380DF6CE58D2' -derivedDataPath build/dd build 2>&1 \
  | grep -E "error:|\*\* BUILD"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Screenshot the search panel and the exclusivity**

Launch with `SIMCTL_CHILD_BP_OPEN_PANELS=filter` plus `BP_OPEN_BAND=1`, then in the simulator tap the
Search toggle.

**Look at it.** Required: the Filter row **disappears** when Search opens (they are mutually exclusive)
and any active status chip is cleared. Type into the field and confirm the count in the nav bar drops.

- [ ] **Step 5: Commit**

```bash
git add band-pilot-ios/Views/Songs/Header/SongSearchField.swift \
        band-pilot-ios/Views/Songs/Header/SongsHeader.swift
git commit -m "Add the Search panel

Hand-built rather than .searchable: the nav bar is full, and the leading magnifier has to close
the section the way every other panel's glyph does."
```

---

### Task 9: The vote-freeze

**Files:**
- Modify: `band-pilot-ios/Views/Songs/SongsView.swift`

**Interfaces:**
- Consumes: `derivedSongs`, `groupKeys(for:)`, `votingSongId`.
- Produces: `frozenOrder: [Int]?`, `frozenGroupKeys: [Int: [String]]?` on `SongsView`, and an `effectiveGroupKeys(for:)` used by `groups`.

- [ ] **Step 1: Add the freeze state and apply it**

```swift
    /// While a voting section is open the displayed order is frozen, so casting a vote cannot
    /// reshuffle the list under the user's thumb. Snapshotted only when a section opens *fresh*:
    /// switching straight to another song keeps the existing snapshot.
    @State private var frozenOrder: [Int]?
    /// Same idea for grouping — a vote must not move a song into a different group mid-tap.
    @State private var frozenGroupKeys: [Int: [String]]?
```

Order:

```swift
    private var displayedSongs: [Song] {
        guard votingSongId != nil, let frozen = frozenOrder else { return derivedSongs }
        // A song absent from the snapshot (added since) sorts last rather than vanishing.
        return derivedSongs.sorted {
            (frozen.firstIndex(of: $0.id) ?? Int.max) < (frozen.firstIndex(of: $1.id) ?? Int.max)
        }
    }
```

Group keys:

```swift
    private func effectiveGroupKeys(for song: Song) -> [String] {
        if votingSongId != nil, let frozen = frozenGroupKeys?[song.id] { return frozen }
        return groupKeys(for: song)
    }
```

- [ ] **Step 2: Snapshot on open, lift on close**

Replace the `onToggleVoting` closure at the `SongRow(...)` call site:

```swift
                                onToggleVoting: {
                                    if votingSongId == song.id {
                                        votingSongId = nil
                                        frozenOrder = nil
                                        frozenGroupKeys = nil
                                    } else {
                                        if votingSongId == nil {
                                            frozenOrder = derivedSongs.map(\.id)
                                            frozenGroupKeys = header.groupBy == nil
                                                ? nil
                                                : Dictionary(
                                                    uniqueKeysWithValues: derivedSongs.map {
                                                        ($0.id, groupKeys(for: $0))
                                                    }
                                                )
                                        }
                                        votingSongId = song.id
                                    }
                                },
```

Then swap the two consumers: `ForEach(derivedSongs)` becomes `ForEach(displayedSongs)`, `groups` uses
`displayedSongs` and `keysOf: effectiveGroupKeys(for:)`, and the media toggle also clears both snapshots
(the media and voting panels are mutually exclusive, so leaving a stale freeze would outlive its reason):

```swift
                                onMedia: {
                                    mediaSong = song
                                    votingSongId = nil
                                    frozenOrder = nil
                                    frozenGroupKeys = nil
                                },
```

The nav-bar count keeps using `derivedSongs.count` — the freeze reorders, it never filters.

- [ ] **Step 3: Build**

```bash
cd /Users/rob/git/roadie/band-pilot-ios
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project band-pilot-ios.xcodeproj \
  -scheme band-pilot-ios -configuration Debug \
  -destination 'id=5D8D1D4E-162C-46E3-95A9-380DF6CE58D2' -derivedDataPath build/dd build 2>&1 \
  | grep -E "error:|\*\* BUILD"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Verify the freeze holds**

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=5D8D1D4E-162C-46E3-95A9-380DF6CE58D2
xcrun simctl install $SIM build/dd/Build/Products/Debug-iphonesimulator/band-pilot-ios.app
xcrun simctl terminate $SIM net.bandpilot 2>/dev/null
SIMCTL_CHILD_BP_AUTOLOGIN_EMAIL=john.doe@bandpilot.net \
SIMCTL_CHILD_BP_AUTOLOGIN_PASSWORD=bandpilot \
SIMCTL_CHILD_BP_OPEN_BAND=1 SIMCTL_CHILD_BP_OPEN_VOTING=1 \
xcrun simctl launch $SIM net.bandpilot
sleep 11
xcrun simctl io $SIM screenshot /tmp/freeze-before.png
```

With the sort on Rating, cast a vote in the open section in the simulator and screenshot again. **The
song must stay where it is.** Close the section and screenshot once more: now it may move. If it moves
while the section is open, the freeze is not being consulted.

- [ ] **Step 5: Commit**

```bash
git add band-pilot-ios/Views/Songs/SongsView.swift
git commit -m "Freeze the list order while a voting section is open

Rating a song no longer reshuffles the list under the user's thumb, and grouping keys are frozen
too so a vote cannot move a song to another group mid-tap. Snapshot taken only on a fresh open."
```

---

### Task 10: Verification pass

**Files:** none — this task runs things and looks at the results.

- [ ] **Step 1: Full unit suite**

```bash
cd /Users/rob/git/roadie/band-pilot-ios/BandPilotKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test 2>&1 \
  | grep -E "Executed [0-9]+ tests, with|error:" | tail -2
```

Expected: `0 failures`. Report the actual count (83 before this plan, +29 from Tasks 1–3, minus the 4
rewritten sorting tests replaced by 8).

- [ ] **Step 2: Clean build, warnings reported not hidden**

```bash
cd /Users/rob/git/roadie/band-pilot-ios
rm -rf build/dd
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project band-pilot-ios.xcodeproj \
  -scheme band-pilot-ios -configuration Debug \
  -destination 'id=5D8D1D4E-162C-46E3-95A9-380DF6CE58D2' -derivedDataPath build/dd build 2>&1 \
  | grep -E "error:|warning:|\*\* BUILD"
```

Expected: `** BUILD SUCCEEDED **`. One pre-existing warning in `Views/Media/AudioPracticePlayer.swift:28`
(Swift 6 concurrency) is not this plan's; report any others.

- [ ] **Step 3: Walk every check, screenshotting each**

1. All five panels open at once — impossible by design: Filter, Group and Search are exclusive. Confirm
   `BP_OPEN_PANELS=details,sort,filter,group,search` resolves to Details + Sort + exactly one of the
   other three, and say which.
2. Each panel individually: Details (8 chips), Sort (chevron on the active chip), Filter (statuses +
   flag chip), Group (5 chips), Search (field, magnifier, clear button).
3. Exclusivity: opening Group with a status filter active clears the filter.
4. A grouped list, collapsed and expanded.
5. The vote-freeze holding order.
6. Reset: everything cleared, all panels closed, sort on Song, rating and flag badges hidden.
7. Persistence: set some state, relaunch without hooks, confirm it survives.
8. The nav bar showing all seven trailing items unclipped.

- [ ] **Step 4: Report honestly**

State what passed, what failed, and what was not checked. If a check failed, say so with the screenshot
— never describe intended behaviour as observed.

- [ ] **Step 5: Commit any fixes the pass produced**

Skip if nothing needed fixing. Do not create an empty commit.

---

## Deliberately not in this plan

- The nav-bar **reload** button Android has and iOS lacks.
- Android's per-member and colour-override flag dimensions — its own UI does not offer them either.
- The media owner filter, which lives inside a song's media panel, not the header.
- Porting these chip rows to `RehearsalView`; Android shares them, iOS's rehearsal screen never had them.
- Android's song-create and share-in features.
