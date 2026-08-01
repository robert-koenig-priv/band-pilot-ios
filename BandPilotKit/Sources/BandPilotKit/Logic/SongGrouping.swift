import Foundation

/// How the songlist may be grouped. Order matches the Group panel's chip order.
public enum GroupBy: String, Sendable, CaseIterable {
    case status, artist, decade, rating, flag
}

/// Which rating the Rating grouping buckets by. Independent of the Rating *display* chip: grouping by
/// the band average while showing your own vote is a legitimate combination.
public enum GroupRatingMode: String, Sendable {
    case band, own
}

public struct SongGroup: Identifiable, Sendable {
    public let key: String
    public let label: String
    public let songs: [Song]
    /// Non-nil only for `.flag` grouping, so the header can draw the flag's colour dot.
    public let flag: Flag?

    public var id: String { key }

    public init(key: String, label: String, songs: [Song], flag: Flag?) {
        self.key = key
        self.label = label
        self.songs = songs
        self.flag = flag
    }
}

public enum SongGrouping {
    public static let unknownArtistKey = "unknown-artist"
    public static let unknownYearKey = "unknown-year"
    public static let unratedKey = "unrated"
    public static let vetoedKey = "vetoed"

    /// Every flag some song actually carries — deduped by flag id, sorted by meaning.
    ///
    /// Deliberately distinct from the band's full catalog, which also contains flags nothing has been
    /// tagged with yet: the Filter chip, the Details toggle and the Flag group order all want the
    /// in-use list, and offering an unused flag as a filter would produce an empty list.
    public static func flagsInUse(_ flags: [Int: [SongFlag]]) -> [Flag] {
        var byId: [Int: Flag] = [:]
        for songFlags in flags.values {
            for f in songFlags where byId[f.flagId] == nil {
                byId[f.flagId] = Flag(
                    id: f.flagId, bandId: 0, meaning: f.meaning,
                    description: f.description, color: f.flagColor
                )
            }
        }
        return byId.values.sorted { $0.meaning.lowercased() < $1.meaning.lowercased() }
    }

    /// A song's group keys. A **list**, because Flag grouping is multi-membership — and an *empty*
    /// list is meaningful: the song appears in no group at all. Only `.flag` can produce that.
    public static func groupKeys(
        for song: Song, by groupBy: GroupBy, flags: [SongFlag], flagOrder: [Int], rating: Double
    ) -> [String] {
        switch groupBy {
        case .status:
            return [song.status.rawValue]
        case .artist:
            let trimmed = (song.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return [trimmed.isEmpty ? unknownArtistKey : trimmed]
        case .decade:
            guard let year = leadingYear(song.year) else { return [unknownYearKey] }
            return [String((year / 10) * 10)]
        case .rating:
            if rating <= Double(RatingMath.vetoValue) { return [vetoedKey] }
            if rating <= 0 { return [unratedKey] }
            return [String(min(5, max(1, Int(rating.rounded()))))]
        case .flag:
            let assigned = Set(flags.map(\.flagId))
            return flagOrder.filter { assigned.contains($0) }.map(String.init)
        }
    }

    public static func groupLabel(for key: String, by groupBy: GroupBy, flagsInUse: [Flag]) -> String {
        switch groupBy {
        case .status:
            return SongStatus(rawValue: key)?.label ?? key
        case .artist:
            return key == unknownArtistKey ? "Unknown artist" : key
        case .decade:
            return key == unknownYearKey ? "Unknown year" : "\(key)s"
        case .rating:
            if key == vetoedKey { return "Vetoed" }
            if key == unratedKey { return "Not rated" }
            return key == "1" ? "1 Star" : "\(key) Stars"
        case .flag:
            return flagsInUse.first { String($0.id) == key }?.meaning ?? key
        }
    }

    /// Bucket, then order the buckets per criterion. `keysOf` is injected so the caller can supply the
    /// frozen keys a voting section needs (see the vote-freeze) instead of the live ones.
    public static func groupSongs(
        _ songs: [Song], by groupBy: GroupBy, flagsInUse: [Flag], keysOf: (Song) -> [String]
    ) -> [SongGroup] {
        var buckets: [String: [Song]] = [:]
        var order: [String] = []
        for song in songs {
            for key in keysOf(song) {
                if buckets[key] == nil { order.append(key) }
                buckets[key, default: []].append(song)
            }
        }

        let keys: [String]
        switch groupBy {
        case .status:
            let canonical = ["READY_FOR_STAGE", "NEED_PRACTICE", "SUGGESTED"]
            keys = canonical.filter { buckets[$0] != nil }
        case .rating:
            let canonical = ["5", "4", "3", "2", "1", unratedKey, vetoedKey]
            keys = canonical.filter { buckets[$0] != nil }
        case .flag:
            keys = flagsInUse.map { String($0.id) }.filter { buckets[$0] != nil }
        case .artist:
            keys = sortedWithUnknownLast(order, unknown: unknownArtistKey) { a, b in
                let (ca, cb) = (buckets[a]?.count ?? 0, buckets[b]?.count ?? 0)
                return ca == cb ? a.lowercased() < b.lowercased() : ca > cb
            }
        case .decade:
            keys = sortedWithUnknownLast(order, unknown: unknownYearKey) {
                (Int($0) ?? 0) < (Int($1) ?? 0)
            }
        }

        return keys.map { key in
            SongGroup(
                key: key,
                label: groupLabel(for: key, by: groupBy, flagsInUse: flagsInUse),
                songs: buckets[key] ?? [],
                flag: groupBy == .flag ? flagsInUse.first { String($0.id) == key } : nil
            )
        }
    }

    /// The year field is a display string and the backend may answer a full ISO date ("1989-06-01"),
    /// so only the leading digits are read. Storing the whole date is what silently breaks decades.
    private static func leadingYear(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let digits = raw.prefix { $0.isNumber }
        return digits.count == 4 ? Int(digits) : nil
    }

    private static func sortedWithUnknownLast(
        _ keys: [String], unknown: String, by areInOrder: (String, String) -> Bool
    ) -> [String] {
        let known = keys.filter { $0 != unknown }.sorted(by: areInOrder)
        return keys.contains(unknown) ? known + [unknown] : known
    }
}
