import Foundation

/// A typed description of one API call. `Response` is the decoded return type.
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    public let method: HTTPMethod
    public let path: String
    public let body: (any Encodable & Sendable)?
    public let requiresAuth: Bool

    public init(
        method: HTTPMethod,
        path: String,
        body: (any Encodable & Sendable)? = nil,
        requiresAuth: Bool = true
    ) {
        self.method = method
        self.path = path
        self.body = body
        self.requiresAuth = requiresAuth
    }
}

/// Type-eraser so the client can encode a heterogeneous `any Encodable` body.
struct AnyEncodable: Encodable {
    private let encodeTo: (Encoder) throws -> Void
    init(_ wrapped: any Encodable) { encodeTo = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeTo(encoder) }
}

// MARK: - Route factories (centralize path strings)

extension Endpoint {
    public static func login(_ req: LoginRequest) -> Endpoint<LoginResponse> {
        .init(method: .post, path: "api/auth/login", body: req, requiresAuth: false)
    }
    public static func register(_ req: RegisterRequest) -> Endpoint<MessageResponse> {
        .init(method: .post, path: "api/auth/register", body: req, requiresAuth: false)
    }
    public static func forgotPassword(_ req: ForgotPasswordRequest) -> Endpoint<MessageResponse> {
        .init(method: .post, path: "api/auth/forgot-password", body: req, requiresAuth: false)
    }
    public static var bands: Endpoint<[Band]> {
        .init(method: .get, path: "api/bands")
    }
    public static func members(bandId: Int) -> Endpoint<[Membership]> {
        .init(method: .get, path: "api/bands/\(bandId)/members")
    }
    public static func bandMembers(bandId: Int) -> Endpoint<[BandMember]> {
        .init(method: .get, path: "api/bands/\(bandId)/band-members")
    }
    public static func flags(bandId: Int) -> Endpoint<[Flag]> {
        .init(method: .get, path: "api/bands/\(bandId)/flags")
    }
    public static func songsWithRatings(bandId: Int) -> Endpoint<[SongWithRatings]> {
        .init(method: .get, path: "api/bands/\(bandId)/songs-with-ratings")
    }
    public static func updateSong(bandId: Int, songId: Int, _ req: SongRequest) -> Endpoint<Song> {
        .init(method: .put, path: "api/bands/\(bandId)/songs/\(songId)", body: req)
    }
    public static func createRating(bandId: Int, songId: Int, _ req: RatingCreateRequest) -> Endpoint<SongRating> {
        .init(method: .post, path: "api/bands/\(bandId)/songs/\(songId)/ratings", body: req)
    }
    public static func updateRating(bandId: Int, songId: Int, ratingId: Int, _ req: RatingUpdateRequest) -> Endpoint<SongRating> {
        .init(method: .put, path: "api/bands/\(bandId)/songs/\(songId)/ratings/\(ratingId)", body: req)
    }
    public static func deleteRating(bandId: Int, songId: Int, ratingId: Int) -> Endpoint<EmptyResponse> {
        .init(method: .delete, path: "api/bands/\(bandId)/songs/\(songId)/ratings/\(ratingId)")
    }
    public static func createFlag(bandId: Int, songId: Int, _ req: FlagCreateRequest) -> Endpoint<SongFlag> {
        .init(method: .post, path: "api/bands/\(bandId)/songs/\(songId)/flags", body: req)
    }
    public static func deleteFlag(bandId: Int, songId: Int, flagAssignmentId: Int) -> Endpoint<EmptyResponse> {
        .init(method: .delete, path: "api/bands/\(bandId)/songs/\(songId)/flags/\(flagAssignmentId)")
    }
}
