import Foundation

/// Parsing/formatting of the zoneless `plannedAt` string, and the default-selection heuristic —
/// mirrors the Android RehearsalViewModel's `defaultRehearsalId`.
public enum RehearsalScheduling {
    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = .current
        return f
    }()

    public static func date(from iso: String) -> Date? { isoFormatter.date(from: iso) }
    public static func iso(from date: Date) -> String { isoFormatter.string(from: date) }

    /// Sort rehearsals chronologically (ISO strings sort lexically = chronologically).
    public static func sorted(_ rehearsals: [Rehearsal]) -> [Rehearsal] {
        rehearsals.sorted { $0.plannedAt < $1.plannedAt }
    }

    /// The earliest non-canceled rehearsal today-or-later; else the most recent non-canceled past
    /// one; else nil. Assumes `rehearsals` is already sorted ascending.
    public static func defaultRehearsalId(_ rehearsals: [Rehearsal], now: Date = Date(), calendar: Calendar = .current) -> Int? {
        let candidates = rehearsals.filter { $0.status != .canceled }
        let today = calendar.startOfDay(for: now)
        let upcoming = candidates.filter { r in
            guard let d = date(from: r.plannedAt) else { return false }
            return calendar.startOfDay(for: d) >= today
        }
        return (upcoming.first ?? candidates.last)?.id
    }
}
