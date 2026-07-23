import Foundation

// All structs mirror the backend JSON by-name (camelCase keys), so no custom
// CodingKeys are needed except where a field may be absent (see BandSong).

public struct User: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let email: String
    public let firstName: String
    public let lastName: String
    public let emailVerified: Bool

    public var fullName: String { "\(firstName) \(lastName)" }

    public init(id: Int, email: String, firstName: String, lastName: String, emailVerified: Bool) {
        self.id = id; self.email = email; self.firstName = firstName
        self.lastName = lastName; self.emailVerified = emailVerified
    }
}

public struct Band: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let tagline: String?
    public let description: String?
    public let location: String?
    public let founded: String?
    public let homepage: String?
    /// The caller's role in this band. `GET /api/bands` includes it, so the bands list can show
    /// the role badge without a separate per-band memberships call.
    public let securityRole: SecurityRole?
}

public struct BandMember: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let bandId: Int
    public let nickName: String
}

/// Item of `GET .../members` — the caller learns its own securityRole + bandMemberId here.
public struct Membership: Codable, Sendable, Hashable {
    public let bandMemberId: Int
    public let nickName: String
    public let userId: Int
    public let email: String
    public let firstName: String
    public let lastName: String
    public let securityRole: SecurityRole
}

/// Catalog flag definition (`GET .../flags`).
public struct Flag: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let bandId: Int
    public let meaning: String
    public let description: String?
    public let color: String
}

public struct SongRating: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let bandSongId: Int
    public let bandMemberId: Int
    public let rating: Int

    public init(id: Int, bandSongId: Int, bandMemberId: Int, rating: Int) {
        self.id = id; self.bandSongId = bandSongId; self.bandMemberId = bandMemberId; self.rating = rating
    }
}

/// A flag assigned to a song. `effectiveColor` mirrors the Android `effectiveColor()`.
public struct BandSongFlag: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let bandSongId: Int
    public let flagId: Int
    public let meaning: String
    public let description: String?
    public let meaningDetails: String?
    public let color: String?
    public let flagColor: String
    public let bandMemberId: Int?

    public var effectiveColor: String { color ?? flagColor }
}

public struct BandSong: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let bandId: Int
    public var name: String
    public var artist: String?
    public var year: String?
    public var originalKey: String?
    public var key: String?
    public var originalBpm: Int?
    public var bpm: Int?
    public var durationSec: Int?
    public var comments: String?
    public var status: SongStatus
    /// Server-computed on the bulk read; absent on the plain song PUT response (defaults to 0.0 then,
    /// and the caller keeps the cached value — a song edit can't change ratings).
    public var averageRating: Double

    public init(
        id: Int, bandId: Int, name: String, artist: String? = nil, year: String? = nil,
        originalKey: String? = nil, key: String? = nil, originalBpm: Int? = nil, bpm: Int? = nil,
        durationSec: Int? = nil, comments: String? = nil, status: SongStatus, averageRating: Double = 0.0
    ) {
        self.id = id; self.bandId = bandId; self.name = name; self.artist = artist; self.year = year
        self.originalKey = originalKey; self.key = key; self.originalBpm = originalBpm; self.bpm = bpm
        self.durationSec = durationSec; self.comments = comments; self.status = status
        self.averageRating = averageRating
    }

    private enum CodingKeys: String, CodingKey {
        case id, bandId, name, artist, year, originalKey, key, originalBpm, bpm, durationSec, comments, status, averageRating
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        bandId = try c.decode(Int.self, forKey: .bandId)
        name = try c.decode(String.self, forKey: .name)
        artist = try c.decodeIfPresent(String.self, forKey: .artist)
        year = try c.decodeIfPresent(String.self, forKey: .year)
        originalKey = try c.decodeIfPresent(String.self, forKey: .originalKey)
        key = try c.decodeIfPresent(String.self, forKey: .key)
        originalBpm = try c.decodeIfPresent(Int.self, forKey: .originalBpm)
        bpm = try c.decodeIfPresent(Int.self, forKey: .bpm)
        durationSec = try c.decodeIfPresent(Int.self, forKey: .durationSec)
        comments = try c.decodeIfPresent(String.self, forKey: .comments)
        status = try c.decode(SongStatus.self, forKey: .status)
        averageRating = try c.decodeIfPresent(Double.self, forKey: .averageRating) ?? 0.0
    }
}

/// Item of the bulk `GET .../songs-with-ratings`: a song plus its ratings and flags.
public struct BandSongWithRatings: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let bandId: Int
    public let name: String
    public let artist: String?
    public let year: String?
    public let originalKey: String?
    public let key: String?
    public let originalBpm: Int?
    public let bpm: Int?
    public let durationSec: Int?
    public let comments: String?
    public let status: SongStatus
    public let averageRating: Double
    public let ratings: [SongRating]
    public let flags: [BandSongFlag]

    private enum CodingKeys: String, CodingKey {
        case id, bandId, name, artist, year, originalKey, key, originalBpm, bpm, durationSec, comments, status, averageRating, ratings, flags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        bandId = try c.decode(Int.self, forKey: .bandId)
        name = try c.decode(String.self, forKey: .name)
        artist = try c.decodeIfPresent(String.self, forKey: .artist)
        year = try c.decodeIfPresent(String.self, forKey: .year)
        originalKey = try c.decodeIfPresent(String.self, forKey: .originalKey)
        key = try c.decodeIfPresent(String.self, forKey: .key)
        originalBpm = try c.decodeIfPresent(Int.self, forKey: .originalBpm)
        bpm = try c.decodeIfPresent(Int.self, forKey: .bpm)
        durationSec = try c.decodeIfPresent(Int.self, forKey: .durationSec)
        comments = try c.decodeIfPresent(String.self, forKey: .comments)
        status = try c.decode(SongStatus.self, forKey: .status)
        averageRating = try c.decodeIfPresent(Double.self, forKey: .averageRating) ?? 0.0
        ratings = try c.decodeIfPresent([SongRating].self, forKey: .ratings) ?? []
        flags = try c.decodeIfPresent([BandSongFlag].self, forKey: .flags) ?? []
    }

    /// The plain `BandSong` projection (as the Android `toSong()` split does).
    public var song: BandSong {
        BandSong(
            id: id, bandId: bandId, name: name, artist: artist, year: year, originalKey: originalKey,
            key: key, originalBpm: originalBpm, bpm: bpm, durationSec: durationSec, comments: comments,
            status: status, averageRating: averageRating
        )
    }
}
