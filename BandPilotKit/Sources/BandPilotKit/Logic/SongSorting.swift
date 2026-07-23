import Foundation

public enum SongSort: String, Sendable, CaseIterable {
    case practiceOrder
    case name
    case artist
}

/// Local filtering + sorting of the cached song list (mirrors the Android page's derived list).
public enum SongSorting {
    public static func filtered(_ songs: [BandSong], status: SongStatus?) -> [BandSong] {
        guard let status else { return songs }
        return songs.filter { $0.status == status }
    }

    public static func sorted(_ songs: [BandSong], by sort: SongSort) -> [BandSong] {
        switch sort {
        case .practiceOrder:
            // status rank (NEED_PRACTICE → SUGGESTED → READY_FOR_STAGE), then rating descending.
            return songs.sorted { a, b in
                if a.status.practiceRank != b.status.practiceRank {
                    return a.status.practiceRank < b.status.practiceRank
                }
                return a.averageRating > b.averageRating
            }
        case .name:
            return songs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .artist:
            return songs.sorted {
                ($0.artist ?? "").localizedCaseInsensitiveCompare($1.artist ?? "") == .orderedAscending
            }
        }
    }

    /// Filter then sort, as the page does for its visible list.
    public static func visible(_ songs: [BandSong], status: SongStatus?, sort: SongSort) -> [BandSong] {
        sorted(filtered(songs, status: status), by: sort)
    }
}
