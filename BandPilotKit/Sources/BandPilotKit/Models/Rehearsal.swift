import Foundation

public enum RehearsalStatus: String, Codable, Sendable, Hashable {
    case planned = "PLANNED"
    case canceled = "CANCELED"
}

/// Flat list item (`GET .../rehearsals`). `plannedAt` is a zoneless ISO LocalDateTime string
/// ("yyyy-MM-dd'T'HH:mm:ss"), kept as-is like the Android model.
public struct Rehearsal: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let bandId: Int
    public var plannedAt: String
    public var status: RehearsalStatus

    public init(id: Int, bandId: Int, plannedAt: String, status: RehearsalStatus) {
        self.id = id; self.bandId = bandId; self.plannedAt = plannedAt; self.status = status
    }
}

/// Full rehearsal (`GET .../rehearsals/{id}`): adds the setlist and missing members.
public struct RehearsalDetail: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let bandId: Int
    public var plannedAt: String
    public var status: RehearsalStatus
    public var songs: [RehearsalSong]
    public var missingMembers: [RehearsalMissingMember]

    /// The flat projection, for patching the list after create/clone.
    public var summary: Rehearsal { Rehearsal(id: id, bandId: bandId, plannedAt: plannedAt, status: status) }
}

public struct RehearsalSong: Codable, Sendable, Identifiable, Hashable {
    public let id: Int          // the join-row id (used for reorder/remove)
    public let rehearsalId: Int
    public let songId: Int
    public let songName: String
    public let artist: String?
    public var ordering: Int
    public var details: String?
}

public struct RehearsalMissingMember: Codable, Sendable, Identifiable, Hashable {
    public let id: Int          // the join-row id (used for un-marking)
    public let rehearsalId: Int
    public let bandMemberId: Int
    public let nickName: String
    public var detail: String?
}
