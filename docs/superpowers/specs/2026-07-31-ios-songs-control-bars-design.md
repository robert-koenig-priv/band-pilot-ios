# iOS songs-screen control bars — design

Date: 2026-07-31
Status: approved, not yet implemented
Scope: `band-pilot-ios` only. Android is the reference and is **not** modified.
Predecessor: `2026-07-30-ios-navigation-drawer-design.md`, which freed the nav bar this needs.

## Why

Android's songs screen carries five header control bars — Details, Sort, Group, Filter, Search —
toggled from icon buttons in the top app bar, each a horizontally-scrolling row of pill chips. Every
selection persists. Grouping renders collapsible group headers. iOS has one bar: a row of status chips
plus a sort menu (`SongsView.swift:105-149`), no grouping, no search, no detail visibility, and no
persisted preference anywhere in the app.

## Decisions taken before designing

1. **All five sections in one spec, built in stages.** The shared parts — the toggle row, the chip
   pill, the preference store, the exclusivity rules — get decided once.
2. **The toggles live in a full-width row of their own, directly above the panels.** Count and Reset
   stay in the nav bar.

   ⚠️ **This reverses an earlier decision, and the reason is worth keeping.** The original choice was
   the nav bar, justified by an estimate: back chevron + hamburger (~80pt) plus 7 trailing items at
   ~38pt each ≈ 346pt of a 402pt bar. That estimate was **wrong**. It ignored that iOS 26 groups
   trailing items into a single capsule with its own padding and reserves room for an overflow
   affordance, so only **three** trailing items survive. Built as specified, the bar showed count +
   Reset + one toggle and collapsed the other four into a `•••` menu — where their open/closed tint,
   the entire point of the tint, is invisible. Verified on the iPhone 17 simulator, not calculated.
3. **No title on the Songs screen.** The drawer already highlights Songs, so the page stays identified.
   (The nav bar now has room for a title again, since only count and Reset remain. Keeping it titleless
   is the standing decision; the space is available if that is ever revisited.)
4. **iOS adopts Android's sort model exactly**: `name` / `artist` / `rating` plus a direction flag,
   default `rating`. **`practiceOrder` is deleted** — Android has no status-rank sort.
5. **Reset is in scope; the reload button is not.**
6. **Flag grouping mirrors Android**, including no catch-all bucket: a song carrying no flag appears
   in no group at all while grouped by Flag. Surprising, but a divergence would mean the same band
   seeing different song counts on the two platforms.

## One ambiguity resolved rather than copied

Android's toggle row is ordered **Details, Sort, Group, Filter, Search** (`HeaderSection.entries`), but
its header renders the panels **Filter, Sort, Group, Details, Search**, and the comment above them claims
the two orders match. They do not. iOS uses the **toggle order** for both — Android's stated intent
rather than its code.

## Architecture

The pure arithmetic goes into BandPilotKit, where it can be tested. Android's equivalents are all
`private` inside a 2,733-line composable and have **no tests at all**; this is the one place the port
deliberately does better rather than identically.

### BandPilotKit

| File | Contents |
|---|---|
| `Logic/SongGrouping.swift` *(new)* | `GroupBy`, `GroupRatingMode`, `SongGroup`, `groupKeys(for:)`, `groupLabel(for:)`, per-criterion ordering, `groupSongs(...)`, `flagsInUse(...)` |
| `Logic/SongSorting.swift` *(modify)* | `SongSort` becomes `.name`/`.artist`/`.rating`; `sorted(_:by:descending:)`; `practiceOrder` **deleted** |

The package-level API, so the panels and the plan agree on names:

```swift
public enum SongSort: String, Sendable, CaseIterable { case name, artist, rating }

public enum GroupBy: String, Sendable, CaseIterable { case status, artist, decade, rating, flag }
public enum GroupRatingMode: String, Sendable { case band, own }

public struct SongGroup: Identifiable, Sendable {
    public let key: String          // also the id
    public let label: String
    public let songs: [Song]
    public let flag: Flag?          // non-nil only for .flag grouping, for the header's dot
}

public enum SongSorting {
    public static func filtered(_ songs: [Song], status: SongStatus?, flagId: Int?,
                                flags: [Int: [SongFlag]], search: String) -> [Song]
    public static func sorted(_ songs: [Song], by: SongSort, descending: Bool,
                              ratingOf: (Song) -> Double) -> [Song]
}

public enum SongGrouping {
    /// The flags any song actually carries — deduped, sorted by meaning. Distinct from the band's
    /// full catalog, which also holds flags no song has yet.
    public static func flagsInUse(_ flags: [Int: [SongFlag]]) -> [Flag]

    public static func groupKeys(for song: Song, by: GroupBy, flags: [SongFlag],
                                 flagOrder: [Int], rating: Double) -> [String]
    public static func groupLabel(for key: String, by: GroupBy, flagsInUse: [Flag]) -> String
    public static func groupSongs(_ songs: [Song], by: GroupBy, flagsInUse: [Flag],
                                  keysOf: (Song) -> [String]) -> [SongGroup]
}
```

**The rating is injected, not read**, because two independent ratings are in play: the one the cards and
the sort use (band average, or the member's own vote when the Rating display says so) and the one
grouping uses (`GroupRatingMode`, which is a separate setting). Passing `ratingOf` / `rating` keeps both
callers honest instead of hiding a wrong default inside the package.
| `Tests/…/SongGroupingTests.swift` *(new)* | Group keys, ordering, labels |
| `Tests/…/SongSortingTests.swift` *(modify)* | Rewritten for the new model |

### App target — new `Views/Songs/Header/`

| File | Contents |
|---|---|
| `SongsHeaderState.swift` | `@Observable`: every panel's state, the exclusivity rules, `reset()` |
| `SongPrefs.swift` | The `UserDefaults` wrapper — typed load/save per key |
| `HeaderSection.swift` | `HeaderSection` enum, the nav-bar toggle row, `SectionGlyph`, `HeaderChip` |
| `FilterChips.swift` | Status + flag chips, and the in-use-flag menu |
| `SortChips.swift` | Sort chips with the direction chevron |
| `GroupChips.swift` | Group criterion chips |
| `DetailChips.swift` | The eight detail chips |
| `SongSearchField.swift` | The search field |
| `SongsHeader.swift` | Stacks whichever panels are open |
| `GroupHeader.swift` | The collapsible group row in the list |

### App target — modified

- `SongsView.swift` — hosts `SongsHeader`, consumes the derived list, gains the nav-bar toggles and
  Reset, loses its title. **`FilterSortBar` (`:105-149`) is deleted, not extended**: its chips fill
  blue when active, whereas Android's pill background never changes and communicates selection by
  content tint alone.
- `SongRow.swift` — every detail becomes conditional, and **Key / BPM / Duration are new row
  content**; iOS shows none of the three today.

One file per panel rather than one big header file, because Android's single 131KB file is precisely
why none of this is testable or reviewable there.

## The nav bar and the toggle row

**Nav bar.** Leading: back chevron, hamburger (`.drawerToolbar`). No title. Trailing: the visible song
count (dim) and Reset (`arrow.counterclockwise`, runs `reset()`). Two trailing items, comfortably within
the three iOS actually allows.

**Toggle row.** A full-width row directly above the panels, holding the five toggles in
`HeaderSection.allCases` order:

| Toggle | Symbol |
|---|---|
| Details | `eye` |
| Sort | `arrow.up.arrow.down` |
| Group | `rectangle.stack` |
| Filter | `line.3.horizontal.decrease` |
| Search | `magnifyingglass` |

Each is tinted `Palette.selected` when its panel is open and `Palette.textDim` when closed, 22pt on a
phone and 28pt when `isWide` — a point or two larger than the nav-bar version would have been, since the
row is not competing for width. Evenly distributed across the width so the row reads as a control strip
rather than a huddle of buttons, and it sits above the panel stack so a toggle is adjacent to the panel
it opens.

## Panel visibility and exclusivity

From Android's `SongHeaderSections.toggle` plus its `LaunchedEffect(visibleSections)`:

- Details and Sort coexist with anything.
- Filter / Group / Search are mutually exclusive — opening one closes the other two.
- Opening a panel also clears the others' **state**, not just their visibility:
  - Group opened → clear the status filter, the flag filter and the search text
  - Filter opened → clear grouping and the search text
  - Search opened → clear grouping, the status filter and the flag filter
- Opening any panel scrolls the list to the top.
- Opening Group collapses every group.
- Turning the Media detail off closes any open media panel.

Each panel row begins with a dim 16pt **section glyph** — the section's own icon — which closes that
section when tapped, exactly as its nav-bar toggle would.

## The five panels

Shared chip: a `Palette.bgCard` pill, 22pt icon, **background never changes with selection** — only
content tint does (`selected` when active, `textDim` when not). On a phone an icon-bearing chip shows
the icon alone with its label as the accessibility label; when `isWide` it also shows the text.

### Filter

Chips in order: **Ready for stage** (`checkmark.circle.fill`), **Need practice**
(`wrench.and.screwdriver.fill`), **Suggested** (`questionmark.circle`), then a **Flag** chip shown only
when at least one song carries a flag, tinted with the selected flag's own colour and opening a menu of
the in-use flags (each row a colour dot, the meaning, and its description; the active row's meaning is
`selected`-tinted, with no checkmark).

Statuses and flags are **one exclusive radio group**: picking a status clears the flag filter and vice
versa; tapping the active status clears it. The flag chip itself only opens the menu — clearing happens
by re-picking the active row there. Nothing selected means no filter, which is the default.

### Sort

Chips in order: **Song** (text only, no icon), **Artist** (`music.mic`), **Rating** (`star.fill`). The
active chip carries a 16pt `chevron.down`/`chevron.up`. Tapping the active chip **flips the direction
rather than clearing** it. Selecting Artist calls `ensureVisible(.artist)`; selecting Rating calls
`ensureRatingShown()`.

### Group

Chips in order: **Status** (`checkmark.circle.fill`), **Artist** (`music.mic`), **Decade**
(`calendar`), **Rating**, **Flag** (`flag.fill`). Single-select, and tapping the active chip clears
grouping. Rating instead cycles off → Band → Own → off, its label reading `Rating (Band)` / `Rating
(Own)` when active, and also calls `ensureRatingShown()`. Status calls `ensureVisible(.status)`,
Artist `ensureVisible(.artist)`.

### Details

Eight chips at a tighter 3pt spacing so they fit one phone width, in order: **Flag** visibility toggle
(shown only when some song carries a flag — one boolean for all flags, not per-flag), **Media**
(`play.fill`), **Rating** (three-state: band average → own vote → hidden, its icon changing per state),
**Status** (`checkmark.circle.fill`), **Artist** (`music.mic`), **Key** (`music.note`), **BPM** (text
`BPM`, no icon), **Duration** (text `00:00`, no icon). Multi-select, no exclusivity. Default visible:
Status, Artist, Key, Media.

The song name is always shown. Artist and Duration share the row's second line joined by ` · `.

### Search

A custom field, not `.searchable`: its leading magnifier closes the section and its trailing clear
button appears only when the text is non-empty, which `.searchable` cannot express. Placeholder
`Song or artist…`, matching either case-insensitively. **Not persisted.**

## Grouping

`groupSongs` buckets by `groupKeys(for:)` — a list, because Flag grouping is multi-membership — then
orders the groups per criterion:

| Criterion | Group order | Keys |
|---|---|---|
| Status | Ready for stage, Need practice, Suggested | the status |
| Artist | song count descending, ties alphabetical, `Unknown artist` last | trimmed artist |
| Decade | ascending, `Unknown year` last | `(year / 10) * 10` |
| Rating | 5, 4, 3, 2, 1, `Not rated`, `Vetoed` | rounded, clamped 1–5 |
| Flag | the in-use catalog's order (meaning A→Z) | every flag the song carries |

Labels: `songStatus.label`; `Unknown artist`; `1980s` / `Unknown year`; `5 Stars` but `1 Star`;
`Not rated`; `Vetoed`; a flag's `meaning`.

A song whose `groupKeys` come back empty appears in **no** group. Only Flag can produce that, and it is
deliberate (decision 6). A test pins it so nobody later "fixes" it.

Rendering: `LazyVStack` items keyed `"\(groupKey):\(songId)"` — not the song id alone, precisely because
of Flag multi-membership. Every group starts **collapsed**; expansion state is per group, is not
persisted, and resets when the criterion changes or the Group panel is reopened.

`GroupHeader`: a `chevron.down` rotating −90° when collapsed, an optional flag dot in the flag's colour,
the label, the flag's description (inline when `isWide`, its own line on a phone), and a trailing count
tinted `Palette.selected`.

## The vote-freeze

While a voting section is open, the displayed order **and** each song's group keys are frozen, so
casting a vote cannot reshuffle the list or move a song to another group under the user's thumb. iOS has
no freeze today and does reshuffle, since `visibleSongs` is recomputed on every change.

The snapshot is taken only when a voting section opens **fresh** (none was open); switching directly to
another song keeps the existing snapshot; closing lifts it. A song missing from the snapshot sorts last.

## Persistence

`UserDefaults`, app-global rather than per-band, matching Android's `SharedPreferences` scope.

| Key | Type | Default |
|---|---|---|
| `song-status-filter` | `String?` | none |

| `song-flag-filter` | `Int?` | none |
| `song-sort-order` | `String` | `rating` |
| `song-sort-descending` | `Bool` | `false` |
| `song-header-sections` | `[String]` | empty (all panels closed) |
| `song-rating-display` | `String` | `average` |
| `song-visible-details` | `[String]` | Status, Artist, Key, Media |
| `song-flags-visible` | `Bool` | `true` |
| `song-group-by` | `String?` | none |
| `song-group-rating-mode` | `String` | `band` |

Search text is not persisted. There is **no migration chain**: the keys reuse Android's names, except
the details key drops Android's `-v3` suffix, which exists there only because Android migrated twice.
Unknown stored values are dropped rather than guessed, failing closed like Android's loaders.

One type differs from Android on purpose: `song-status-filter` stores a single optional `String`, where
Android stores a `Set`. Android's set never holds more than one element — its own chip handler assigns
`setOf(status)` or `emptySet()` — so the set is a leftover from a multi-select that no longer exists, and
copying it would mean writing code to defend against a second element that cannot occur.

Two reconciliations run on load, mirroring Android's:

- A stored status filter naming a status that no longer exists is dropped.
- A stored flag id is dropped once the flag catalog loads and does not contain it.
- If a filter and a grouping are both stored, the filter wins and grouping is cleared. If a status and
  a flag are both stored, the status wins.

## Reset

Clears both filters and the search text; sets sort to **`name` ascending**; clears grouping; empties the
visible details; sets the rating display to **hidden**; sets flag badges to **not visible**; closes
every panel; scrolls to the top.

⚠️ Deliberate asymmetry, mirrored from Android: the *default* sort is `rating`, but *reset* leaves it at
`name`. Reset is not "return to defaults", it is "clear everything".

## Testing

**Unit (`BandPilotKit`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`):**

- Comparators for `name`, `artist`, `rating`; the direction flag; rating ties broken by name.
- `groupKeys` per criterion: decade arithmetic, `Unknown artist`, `Unknown year`, the veto / unrated /
  1–5 rating buckets, flag multi-membership, and **empty keys ⇒ the song appears nowhere**.
- Group ordering per criterion, with unknowns last.
- Labels, including the `5 Stars` vs `1 Star` singular.
- `SongPrefs` drops unknown stored values.

**Simulator (iPhone 17, local backend, screenshots kept and looked at):** each panel open; the
Filter/Group/Search exclusivity; a grouped list with collapsed and expanded groups; the vote-freeze
holding order while a voting section is open; Reset returning the screen to bare; and the nav bar
showing all seven trailing items without overflow.

New DEBUG launch hooks will be needed to reach these states headlessly, in the family of the existing
`BP_OPEN_*` ones — `simctl` has no tap command.

## Implementation stages

1. `SongSorting` rewritten to Android's model, `practiceOrder` deleted, tests updated.
2. `SongGrouping` in BandPilotKit with its tests.
3. `SongPrefs` + `SongsHeaderState` with the exclusivity rules and `reset()`.
4. `HeaderChip`, `SectionGlyph`, the nav-bar toggle row; title removed. Verify the bar fits.
5. Filter, Sort and Details panels; `SongRow` made conditional and gaining Key/BPM/Duration.
6. Group panel, `GroupHeader`, grouped rendering.
7. Search panel.
8. The vote-freeze.
9. Verification pass.

## Out of scope

- The nav-bar **reload** button Android has and iOS lacks.
- Android's per-member and colour-override flag dimensions — its own UI does not offer them either.
- The media owner filter, which lives inside a song's media panel, not the header.
- Porting these chip rows to `RehearsalView`; Android shares them, iOS's rehearsal screen never had them.
- Android's newer song-create and share-in features.
