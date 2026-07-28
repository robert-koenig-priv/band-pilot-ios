import Foundation

public struct LoginRequest: Codable, Sendable {
    public let email: String
    public let password: String
    public init(email: String, password: String) { self.email = email; self.password = password }
}

public struct RegisterRequest: Codable, Sendable {
    public let email: String
    public let password: String
    public let firstName: String
    public let lastName: String
    public init(email: String, password: String, firstName: String, lastName: String) {
        self.email = email; self.password = password; self.firstName = firstName; self.lastName = lastName
    }
}

public struct ForgotPasswordRequest: Codable, Sendable {
    public let email: String
    public init(email: String) { self.email = email }
}

public struct LoginResponse: Codable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: Int
    public let user: User
}

public struct MessageResponse: Codable, Sendable {
    public let message: String?
}

/// Body of `PUT .../songs/{id}`. artist is required by the backend (non-null).
public struct SongRequest: Codable, Sendable {
    public var name: String
    public var artist: String
    public var year: String?
    public var originalKey: String?
    public var key: String?
    public var originalBpm: Int?
    public var bpm: Int?
    public var durationSec: Int?
    public var comments: String?
    public var status: SongStatus

    public init(
        name: String, artist: String, year: String? = nil, originalKey: String? = nil, key: String? = nil,
        originalBpm: Int? = nil, bpm: Int? = nil, durationSec: Int? = nil, comments: String? = nil, status: SongStatus
    ) {
        self.name = name; self.artist = artist; self.year = year; self.originalKey = originalKey
        self.key = key; self.originalBpm = originalBpm; self.bpm = bpm; self.durationSec = durationSec
        self.comments = comments; self.status = status
    }
}

public struct RatingCreateRequest: Codable, Sendable {
    public let bandMemberId: Int
    public let rating: Int
    public init(bandMemberId: Int, rating: Int) { self.bandMemberId = bandMemberId; self.rating = rating }
}

public struct RatingUpdateRequest: Codable, Sendable {
    public let rating: Int
    public init(rating: Int) { self.rating = rating }
}

public struct FlagCreateRequest: Codable, Sendable {
    public let flagId: Int
    public let meaningDetails: String?
    public let color: String?
    public let bandMemberId: Int?
    public init(flagId: Int, meaningDetails: String? = nil, color: String? = nil, bandMemberId: Int? = nil) {
        self.flagId = flagId; self.meaningDetails = meaningDetails; self.color = color; self.bandMemberId = bandMemberId
    }
}

/// Sentinel for endpoints returning 204 / no body.
public struct EmptyResponse: Codable, Sendable {
    public init() {}
}
