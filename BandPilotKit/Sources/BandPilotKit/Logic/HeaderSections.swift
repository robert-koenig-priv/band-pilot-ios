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

    public init(attributeFilter: Bool, grouping: Bool, search: Bool) {
        self.attributeFilter = attributeFilter
        self.grouping = grouping
        self.search = search
    }
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
