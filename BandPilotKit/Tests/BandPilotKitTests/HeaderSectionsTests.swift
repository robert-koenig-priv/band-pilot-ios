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
