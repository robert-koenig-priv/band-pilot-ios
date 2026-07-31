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
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
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

extension SongSorting {
    /// Reorders `songs` to match `frozenOrder` (a prior snapshot of song ids); a song absent from
    /// the snapshot sorts last rather than vanishing. Used to freeze list order while a per-song
    /// voting section is open, so a vote cannot reshuffle the list under the user's thumb.
    public static func applyingFreeze(_ songs: [Song], frozenOrder: [Int]) -> [Song] {
        // `uniquingKeysWith:` (keeping the first occurrence), not `uniqueKeysWithValues:`: nothing
        // upstream guarantees `frozenOrder`'s ids are unique, and the `firstIndex(of:)`-based
        // implementation this replaced was inherently duplicate-tolerant. A duplicate id must
        // degrade to an odd order, never a crash.
        let index = Dictionary(
            frozenOrder.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // Every song absent from the snapshot shares the `Int.max` fallback, and `Array.sorted` is
        // explicitly not a stable sort — so ties need an explicit tiebreak rather than relying on
        // input order, which is not guaranteed to survive. Absent songs fall back to id order.
        return songs.sorted { a, b in
            let (ia, ib) = (index[a.id] ?? Int.max, index[b.id] ?? Int.max)
            return ia == ib ? a.id < b.id : ia < ib
        }
    }
}
