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
    public private(set) var songs: [Song] = []
    public private(set) var ratings: [Int: [SongRating]] = [:]   // keyed by songId
    public private(set) var flags: [Int: [SongFlag]] = [:]   // keyed by songId
    public private(set) var flagCatalog: [Flag] = []
    /// Media **links** per song, from one band-scoped call in ``load()``.
    ///
    /// Every song gets a key even when it has no links, which is what stops ``ensureMediaLoaded(songId:)``
    /// from firing per row. Was a per-row lazy fan-out, which is why a refresh never picked up a link
    /// another member had added or deleted.
    public private(set) var mediaLinks: [Int: [MediaLink]] = [:]

    /// Media **files** per song, plus band-level ones under ``bandLevelFilesKey``.
    ///
    /// Unlike links, these come from one band-scoped call: the backend offers a bulk read deliberately,
    /// because a second per-song fan-out on top of the links one would double the request count against
    /// an instance that sleeps after 15 minutes.
    public private(set) var mediaFiles: [Int: [MediaFile]] = [:]

    /// False when the backend predates media files (404 on the list). The upload affordance hides rather
    /// than offering an action that cannot work, so this client stays usable against an older deployment.
    public private(set) var mediaFilesSupported = true

    /// What this member may upload: storage present, terms pending, per-kind size caps.
    public private(set) var uploadPolicy: MediaUploadPolicy?

    /// Which owner's files the panel shows. In-memory: this is a per-session view of one song's panel,
    /// not a page-level preference.
    public var ownerFilter: MediaOwnerFilter = .mineAndBand

    public static let bandLevelFilesKey = -1
    public private(set) var roster: [BandMember] = []
    public private(set) var myBandMemberId: Int?
    public private(set) var isAdmin = false

    /// The caller's raw role in this band, so media affordances can use ``Permissions/canUploadMedia(_:)``
    /// — which is deliberately wider than ``canEditSongs``.
    public private(set) var myRole: SecurityRole?
    public private(set) var canEditSongs = false

    // UI state
    public var isLoading = false
    public var error: APIError?
    public var voteError: String?
    public var flagError: String?
    public var formError: String?

    @ObservationIgnored public let bandId: Int
    @ObservationIgnored private let currentUserId: Int
    @ObservationIgnored /// Exposed so the upload sheet can drive the three-phase upload without a second client.
 public let api: APIClient
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
            // `try?` rather than joining the throwing awaits below: a 404 here means the backend
            // predates the band-wide route, which must degrade to links-on-demand rather than failing
            // the whole screen — the same reasoning as `mediaFilesSupported`.
            //
            // ⚠️ It must stay an `async let`. Writing `let x = try? await api.send(...)` here reads
            // almost identically but suspends *at this line*, so the five fetches above stop
            // overlapping with it and the load gets slower for no reason.
            async let bandLinksF: [MediaLink]? = try? await api.send(.mediaLinks(bandId: bandId))

            let memberships = try await membershipsF
            let rosterList = try await rosterF
            let catalog = try await catalogF
            let allBands = try await allBandsF
            let withRatings = try await withRatingsF
            let bandLinks = await bandLinksF

            roster = rosterList
            flagCatalog = catalog
            band = allBands.first { $0.id == bandId }

            if let me = memberships.first(where: { $0.userId == currentUserId }) {
                myBandMemberId = me.bandMemberId
                myRole = me.securityRole
                isAdmin = Permissions.isAdmin(me.securityRole)
                canEditSongs = Permissions.canEditSongs(me.securityRole)
            }

            songs = withRatings.map(\.song)
            ratings = Dictionary(uniqueKeysWithValues: withRatings.map { ($0.id, $0.ratings) })
            flags = Dictionary(uniqueKeysWithValues: withRatings.map { ($0.id, $0.flags) })

            // Seeded with every song **before** the groups are overlaid, so a song with no links still
            // counts as loaded and `SongRow`'s `.task` does not fire a pointless per-song fetch for it.
            // Assigning the whole map is also what makes this a refresh: the per-row fan-out it replaces
            // could only ever add keys, so a link somebody else deleted stayed on screen.
            //
            // nil means the call failed — leave the map alone and let `ensureMediaLoaded` fall back.
            if let bandLinks {
                var seeded = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, [MediaLink]()) })
                seeded.merge(Dictionary(grouping: bandLinks, by: \.songId)) { _, fetched in fetched }
                mediaLinks = seeded
            }
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

    // MARK: - Media links (one bulk read in load(); per-song fetch is the fallback)

    /// Whether a song has anything at all — link or file. Gates the row's play button.
    public func hasMedia(_ songId: Int) -> Bool {
        !(mediaLinks[songId]?.isEmpty ?? true) || !files(for: songId).isEmpty
    }

    public func files(for songId: Int) -> [MediaFile] { mediaFiles[songId] ?? [] }

    /// One band-scoped call for every file.
    ///
    /// A 404 means this backend has no media-file endpoints yet: degrade to links-only rather than
    /// surfacing an error the user cannot act on.
    public func loadMediaFiles(library: MediaLibrary?) async {
        do {
            let files = try await api.send(.mediaFiles(bandId: bandId))
            mediaFiles = Dictionary(grouping: files) { $0.songId ?? Self.bandLevelFilesKey }
            mediaFilesSupported = true
            // only ever with a SUCCESSFUL list: an empty one must not be read as "all gone"
            library?.reconcile(with: files)
            uploadPolicy = try? await api.send(.mediaUploadPolicy(bandId: bandId))
        } catch APIError.http(let status, _, _) where status == 404 {
            mediaFilesSupported = false
        } catch {
            // links still work; a file-list failure must not blank the whole screen
        }
    }

    /// Patch state from a write response instead of re-fetching, as ratings and flags already do.
    public func fileChanged(_ file: MediaFile) {
        let key = file.songId ?? Self.bandLevelFilesKey
        for (songId, list) in mediaFiles {
            mediaFiles[songId] = list.filter { $0.id != file.id }
        }
        mediaFiles[key] = (mediaFiles[key] ?? []) + [file]
        mediaFiles[key]?.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func deleteFile(_ file: MediaFile, library: MediaLibrary?) async {
        guard (try? await api.send(.deleteMediaFile(bandId: bandId, fileId: file.id))) != nil else { return }
        library?.removeDownload(file)
        for (songId, list) in mediaFiles {
            mediaFiles[songId] = list.filter { $0.id != file.id }
        }
    }

    /// Re-tag a file: `owner` nil hands it to the whole band, otherwise it must be the logged-in user's
    /// own roster entry — the backend refuses anything else for a plain member, and the app never offers
    /// it.
    ///
    /// A full replace on the wire, so the file's own name, kind and song are re-sent unchanged; a partial
    /// body would clear them.
    public func setFileOwner(_ file: MediaFile, to owner: Int?) async {
        let req = MediaFileUpdateRequest(
            name: file.name,
            kind: file.kind,
            songId: file.songId,
            ownerBandMemberId: owner
        )
        guard let updated = try? await api.send(
            .updateMediaFile(bandId: bandId, fileId: file.id, req)
        ) else { return }
        for (songId, list) in mediaFiles {
            mediaFiles[songId] = list.map { $0.id == updated.id ? updated : $0 }
        }
    }

    /// ⚠️ Permanent: a link has no restore, unlike a file. The UI says so before calling this.
    public func deleteLink(_ link: MediaLink) async {
        guard (try? await api.send(
            .deleteMediaLink(bandId: bandId, songId: link.songId, linkId: link.id)
        )) != nil else { return }
        for (songId, list) in mediaLinks {
            mediaLinks[songId] = list.filter { $0.id != link.id }
        }
    }

    /// Re-tag a link; see ``setFileOwner(_:to:)`` for why the whole link is re-sent.
    public func setLinkOwner(_ link: MediaLink, to owner: Int?) async {
        let req = MediaLinkRequest(
            name: link.name,
            mediaType: link.mediaType,
            url: link.url,
            ownerBandMemberId: owner
        )
        guard let updated = try? await api.send(
            .updateMediaLink(bandId: bandId, songId: link.songId, linkId: link.id, req)
        ) else { return }
        for (songId, list) in mediaLinks {
            mediaLinks[songId] = list.map { $0.id == updated.id ? updated : $0 }
        }
    }

    public func media(for songId: Int) -> [MediaLink] { mediaLinks[songId] ?? [] }

    /// One song's links, at most once. The **fallback**: ``load()`` fills the map in one call, so this
    /// no-ops for every song unless that bulk read failed, in which case no song has a key and each row
    /// fetches its own.
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
    public func updateSong(songId: Int, request: SongRequest) async -> Bool {
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
