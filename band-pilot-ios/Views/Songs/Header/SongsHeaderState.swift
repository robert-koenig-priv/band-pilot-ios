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
