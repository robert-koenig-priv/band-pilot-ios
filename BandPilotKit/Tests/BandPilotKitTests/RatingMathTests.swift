import XCTest
@testable import BandPilotKit

final class RatingMathTests: XCTestCase {
    private func ratings(_ values: [Int]) -> [SongRating] {
        values.enumerated().map { SongRating(id: $0.offset, bandSongId: 1, bandMemberId: $0.offset, rating: $0.element) }
    }

    func testEmptyIsZero() {
        XCTAssertEqual(RatingMath.averageRatingOf([]), 0.0)
    }

    func testMeanOfScored() {
        XCTAssertEqual(RatingMath.averageRatingOf(ratings([5, 3, 4])), 4.0, accuracy: 0.0001)
    }

    func testZeroesExcluded() {
        // 0 = "did not rate" → excluded from the mean.
        XCTAssertEqual(RatingMath.averageRatingOf(ratings([4, 0, 2])), 3.0, accuracy: 0.0001)
    }

    func testAllZeroesIsZero() {
        XCTAssertEqual(RatingMath.averageRatingOf(ratings([0, 0])), 0.0)
    }

    func testVetoWinsRegardlessOfOthers() {
        XCTAssertEqual(RatingMath.averageRatingOf(ratings([5, 5, -1, 4])), -1.0)
    }

    func testSingleVeto() {
        XCTAssertEqual(RatingMath.averageRatingOf(ratings([-1])), -1.0)
    }
}
