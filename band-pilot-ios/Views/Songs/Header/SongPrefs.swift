import Foundation
import BandPilotKit

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

    /// Folds the stored set through `HeaderSections.toggling` — opening each stored section in
    /// `allCases` order, exactly as the UI would — so a combination the UI itself could never produce
    /// (e.g. a future build's `["filter","group","search"]`, or one poked in via the DEBUG
    /// `BP_OPEN_PANELS` hook) reduces to a legal one instead of stranding this build with three
    /// mutually-exclusive panels open and none of the state-clears having run.
    static func sections() -> Set<HeaderSection> {
        let raw = defaults.stringArray(forKey: Key.headerSections) ?? []
        let loaded = Set(raw.compactMap(HeaderSection.init(rawValue:)))
        return HeaderSection.allCases
            .filter(loaded.contains)
            .reduce(into: Set<HeaderSection>()) { acc, section in
                acc = HeaderSections.toggling(section, in: acc)
            }
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
