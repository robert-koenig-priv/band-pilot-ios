import Foundation

/// Client-side mirror of the backend's average-rating rule. Kept identical to the
/// Android `averageRatingOf` so the app can patch a song's average locally after a
/// vote write instead of re-fetching.
///
/// Rating semantics: 1...5 = stars, 0 = "did not rate" (excluded), -1 = veto.
public enum RatingMath {
    /// A single veto forces the average, regardless of other votes.
    public static let vetoValue = -1

    public static func averageRatingOf(_ ratings: [SongRating]) -> Double {
        if ratings.contains(where: { $0.rating == vetoValue }) { return -1.0 }
        let scored = ratings.map(\.rating).filter { (1...5).contains($0) } // 0 = didn't rate, excluded
        guard !scored.isEmpty else { return 0.0 }
        return Double(scored.reduce(0, +)) / Double(scored.count)
    }
}
