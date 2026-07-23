import Foundation

extension Endpoint {
    public static func rehearsals(bandId: Int) -> Endpoint<[Rehearsal]> {
        .init(method: .get, path: "api/bands/\(bandId)/rehearsals")
    }
    public static func createRehearsal(bandId: Int, _ req: RehearsalRequest) -> Endpoint<Rehearsal> {
        .init(method: .post, path: "api/bands/\(bandId)/rehearsals", body: req)
    }
    public static func rehearsalDetail(bandId: Int, id: Int) -> Endpoint<RehearsalDetail> {
        .init(method: .get, path: "api/bands/\(bandId)/rehearsals/\(id)")
    }
    public static func cloneRehearsal(bandId: Int, id: Int, _ req: RehearsalCloneRequest) -> Endpoint<RehearsalDetail> {
        .init(method: .post, path: "api/bands/\(bandId)/rehearsals/\(id)/clone", body: req)
    }
    public static func updateRehearsal(bandId: Int, id: Int, _ req: RehearsalRequest) -> Endpoint<Rehearsal> {
        .init(method: .put, path: "api/bands/\(bandId)/rehearsals/\(id)", body: req)
    }
    public static func deleteRehearsal(bandId: Int, id: Int) -> Endpoint<EmptyResponse> {
        .init(method: .delete, path: "api/bands/\(bandId)/rehearsals/\(id)")
    }
    public static func addRehearsalSong(bandId: Int, rehearsalId: Int, _ req: RehearsalSongRequest) -> Endpoint<RehearsalSong> {
        .init(method: .post, path: "api/bands/\(bandId)/rehearsals/\(rehearsalId)/songs", body: req)
    }
    public static func updateRehearsalSong(bandId: Int, rehearsalId: Int, songRowId: Int, _ req: RehearsalSongRequest) -> Endpoint<RehearsalSong> {
        .init(method: .put, path: "api/bands/\(bandId)/rehearsals/\(rehearsalId)/songs/\(songRowId)", body: req)
    }
    public static func removeRehearsalSong(bandId: Int, rehearsalId: Int, songRowId: Int) -> Endpoint<EmptyResponse> {
        .init(method: .delete, path: "api/bands/\(bandId)/rehearsals/\(rehearsalId)/songs/\(songRowId)")
    }
    public static func addMissingMember(bandId: Int, rehearsalId: Int, _ req: RehearsalMissingMemberRequest) -> Endpoint<RehearsalMissingMember> {
        .init(method: .post, path: "api/bands/\(bandId)/rehearsals/\(rehearsalId)/missing-members", body: req)
    }
    public static func removeMissingMember(bandId: Int, rehearsalId: Int, rowId: Int) -> Endpoint<EmptyResponse> {
        .init(method: .delete, path: "api/bands/\(bandId)/rehearsals/\(rehearsalId)/missing-members/\(rowId)")
    }
}
