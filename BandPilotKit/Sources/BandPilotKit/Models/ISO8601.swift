import Foundation

/// Parsing the ISO-8601 timestamps the backend sends.
///
/// Exists because `ISO8601DateFormatter` **fails** on fractional seconds unless told to expect them,
/// and Jackson's default `Instant` serialization emits them. Getting this wrong makes every envelope
/// look expired, which is the kind of bug that reads as "the server is broken".
///
/// Formatters are cached: creating one per call is measurably slow and this runs per file.
public enum ISO8601 {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let withoutFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Tolerates `Z` and an explicit offset, with or without fractional seconds.
    public static func date(from text: String) -> Date? {
        withFraction.date(from: text) ?? withoutFraction.date(from: text)
    }
}
