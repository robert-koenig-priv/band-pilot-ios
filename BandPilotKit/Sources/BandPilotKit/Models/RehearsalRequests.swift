import Foundation

public struct RehearsalRequest: Codable, Sendable {
    public var plannedAt: String
    public var status: RehearsalStatus
    public init(plannedAt: String, status: RehearsalStatus = .planned) {
        self.plannedAt = plannedAt; self.status = status
    }
}

public struct RehearsalCloneRequest: Codable, Sendable {
    public var plannedAt: String?
    public init(plannedAt: String? = nil) { self.plannedAt = plannedAt }
}

public struct RehearsalSongRequest: Codable, Sendable {
    public var songId: Int
    public var ordering: Int?
    public var details: String?
    public init(songId: Int, ordering: Int? = nil, details: String? = nil) {
        self.songId = songId; self.ordering = ordering; self.details = details
    }
}

public struct RehearsalMissingMemberRequest: Codable, Sendable {
    public var bandMemberId: Int
    public var detail: String?
    public init(bandMemberId: Int, detail: String? = nil) {
        self.bandMemberId = bandMemberId; self.detail = detail
    }
}
