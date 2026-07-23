import Foundation
import Observation

/// Songs/ratings/flags for one band. Mirrors the Android BandDetailViewModel: a parallel load
/// fan-out into an in-memory cache, and writes that patch the cache from the response (recomputing
/// the average locally) instead of re-fetching.
@MainActor
@Observable
public final class BandDetailViewModel {
    // Cache
    public private(set) var band: Band?
    public private(set) var songs: [BandSong] = []
    public private(set) var ratings: [Int: [SongRating]] = [:]   // keyed by songId
    public private(set) var flags: [Int: [BandSongFlag]] = [:]   // keyed by songId
    public private(set) var flagCatalog: [Flag] = []
    public private(set) var mediaLinks: [Int: [MediaLink]] = [:]   // keyed by songId (lazily loaded)
    public private(set) var roster: [BandMember] = []
    public private(set) var myBandMemberId: Int?
    public private(set) var isAdmin = false
    public private(set) var canEditSongs = false

    // UI state
    public var isLoading = false
    public var error: APIError?
    public var voteError: String?
    public var flagError: String?
    public var formError: String?

    // Filter/sort (drive the derived list)
    public var statusFilter: SongStatus?
    public var sort: SongSort = .practiceOrder

    public var visibleSongs: [BandSong] {
        SongSorting.visible(songs, status: statusFilter, sort: sort)
    }

    @ObservationIgnored public let bandId: Int
    @ObservationIgnored private let currentUserId: Int
    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var mediaInFlight: Set<Int> = []

    public init(bandId: Int, currentUserId: Int, api: APIClient) {
        self.bandId = bandId
        self.currentUserId = currentUserId
        self.api = api
    }

    public func load() async {
        isLoading = true
        error = nil
        do {
            async let membershipsF = api.send(.members(bandId: bandId))
            async let rosterF = api.send(.bandMembers(bandId: bandId))
            async let catalogF = api.send(.flags(bandId: bandId))
            async let allBandsF = api.send(.bands)
            async let withRatingsF = api.send(.songsWithRatings(bandId: bandId))

            let memberships = try await membershipsF
            let rosterList = try await rosterF
            let catalog = try await catalogF
            let allBands = try await allBandsF
            let withRatings = try await withRatingsF

            roster = rosterList
            flagCatalog = catalog
            band = allBands.first { $0.id == bandId }

            if let me = memberships.first(where: { $0.userId == currentUserId }) {
                myBandMemberId = me.bandMemberId
                isAdmin = Permissions.isAdmin(me.securityRole)
                canEditSongs = Permissions.canEditSongs(me.securityRole)
            }

            songs = withRatings.map(\.song)
            ratings = Dictionary(uniqueKeysWithValues: withRatings.map { ($0.id, $0.ratings) })
            flags = Dictionary(uniqueKeysWithValues: withRatings.map { ($0.id, $0.flags) })
        } catch let apiError as APIError {
            error = apiError
        } catch let other {
            error = .transport(other.localizedDescription)
        }
        isLoading = false
    }

    // MARK: - Voting (self-only unless admin)

    public func castVote(songId: Int, memberId: Int, rating: Int) async {
        guard Permissions.canVoteFor(memberId: memberId, myBandMemberId: myBandMemberId, isAdmin: isAdmin) else {
            voteError = "You can only change your own vote."
            return
        }
        voteError = nil
        let existing = ratings[songId]?.first { $0.bandMemberId == memberId }
        do {
            if let existing {
                if rating == 0 {
                    // clearing a rating deletes the record
                    _ = try await api.send(.deleteRating(bandId: bandId, songId: songId, ratingId: existing.id))
                    ratings[songId]?.removeAll { $0.id == existing.id }
                } else {
                    let updated = try await api.send(.updateRating(bandId: bandId, songId: songId, ratingId: existing.id, .init(rating: rating)))
                    upsertRating(updated, songId: songId)
                }
            } else if rating != 0 {
                let created = try await api.send(.createRating(bandId: bandId, songId: songId, .init(bandMemberId: memberId, rating: rating)))
                upsertRating(created, songId: songId)
            }
            recomputeAverage(songId: songId)
        } catch let apiError as APIError {
            voteError = apiError.userMessage
        } catch let other {
            voteError = other.localizedDescription
        }
    }

    /// The member's own current vote (0 = not voted).
    public func individualRating(songId: Int, memberId: Int) -> Int {
        ratings[songId]?.first { $0.bandMemberId == memberId }?.rating ?? 0
    }

    // MARK: - Media links (lazily fetched per song, no bulk read)

    public func hasMedia(_ songId: Int) -> Bool { !(mediaLinks[songId]?.isEmpty ?? true) }
    public func media(for songId: Int) -> [MediaLink] { mediaLinks[songId] ?? [] }

    /// Fetch a song's media links once (called as rows appear). No-ops if already loaded/in-flight.
    public func ensureMediaLoaded(songId: Int) async {
        guard mediaLinks[songId] == nil, !mediaInFlight.contains(songId) else { return }
        mediaInFlight.insert(songId)
        defer { mediaInFlight.remove(songId) }
        if let links = try? await api.send(.mediaLinks(bandId: bandId, songId: songId)) {
            mediaLinks[songId] = links
        }
    }

    // MARK: - Flags (band-wide assign/unassign)

    public func assignFlag(songId: Int, flagId: Int) async {
        flagError = nil
        do {
            let created = try await api.send(.createFlag(bandId: bandId, songId: songId, .init(flagId: flagId)))
            flags[songId, default: []].append(created)
        } catch let apiError as APIError {
            flagError = apiError.userMessage
        } catch let other {
            flagError = other.localizedDescription
        }
    }

    public func removeFlag(songId: Int, assignmentId: Int) async {
        flagError = nil
        do {
            _ = try await api.send(.deleteFlag(bandId: bandId, songId: songId, flagAssignmentId: assignmentId))
            flags[songId]?.removeAll { $0.id == assignmentId }
        } catch let apiError as APIError {
            flagError = apiError.userMessage
        } catch let other {
            flagError = other.localizedDescription
        }
    }

    // MARK: - Song edit

    @discardableResult
    public func updateSong(songId: Int, request: BandSongRequest) async -> Bool {
        formError = nil
        do {
            var updated = try await api.send(.updateSong(bandId: bandId, songId: songId, request))
            if let idx = songs.firstIndex(where: { $0.id == songId }) {
                // The PUT response has no averageRating; keep the cached one (an edit can't change ratings).
                updated.averageRating = songs[idx].averageRating
                songs[idx] = updated
            }
            return true
        } catch let apiError as APIError {
            formError = apiError.userMessage
            return false
        } catch let other {
            formError = other.localizedDescription
            return false
        }
    }

    // MARK: - Cache helpers

    private func upsertRating(_ rating: SongRating, songId: Int) {
        var list = ratings[songId] ?? []
        if let idx = list.firstIndex(where: { $0.id == rating.id }) {
            list[idx] = rating
        } else if let idx = list.firstIndex(where: { $0.bandMemberId == rating.bandMemberId }) {
            list[idx] = rating
        } else {
            list.append(rating)
        }
        ratings[songId] = list
    }

    private func recomputeAverage(songId: Int) {
        guard let idx = songs.firstIndex(where: { $0.id == songId }) else { return }
        songs[idx].averageRating = RatingMath.averageRatingOf(ratings[songId] ?? [])
    }
}
