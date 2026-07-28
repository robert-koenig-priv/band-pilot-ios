import Foundation
import Observation

/// A band's rehearsals: the flat list (for prev/next + default selection) plus the selected
/// rehearsal's detail (songs + missing members). Mutations patch `detail`/`rehearsals` in place
/// from the write response — no re-fetch (except a failed reorder, which re-fetches to resync).
@MainActor
@Observable
public final class RehearsalViewModel {
    public private(set) var rehearsals: [Rehearsal] = []
    public private(set) var selectedId: Int?
    public private(set) var detail: RehearsalDetail?
    public private(set) var catalog: [Song] = []   // band songs, for the add picker
    public private(set) var roster: [BandMember] = []  // for the missing-members picker

    public var isLoading = false
    public var detailLoading = false
    public var error: APIError?
    public var formError: String?

    @ObservationIgnored private let bandId: Int
    @ObservationIgnored private let api: APIClient

    public init(bandId: Int, api: APIClient) {
        self.bandId = bandId
        self.api = api
    }

    public var selectedIndex: Int? { rehearsals.firstIndex { $0.id == selectedId } }
    public var hasPrevious: Bool { (selectedIndex ?? 0) > 0 }
    public var hasNext: Bool {
        guard let i = selectedIndex else { return false }
        return i < rehearsals.count - 1
    }

    /// Catalog songs not already in the selected rehearsal, by name.
    public var availableSongs: [Song] {
        let present = Set((detail?.songs ?? []).map(\.songId))
        return catalog.filter { !present.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Roster members not already marked missing.
    public var availableMembers: [BandMember] {
        let present = Set((detail?.missingMembers ?? []).map(\.bandMemberId))
        return roster.filter { !present.contains($0.id) }
    }

    public func load() async {
        isLoading = true
        error = nil
        do {
            async let listF = api.send(.rehearsals(bandId: bandId))
            async let catalogF = api.send(.songsWithRatings(bandId: bandId))
            async let rosterF = api.send(.bandMembers(bandId: bandId))
            let (list, cat, ros) = try await (listF, catalogF, rosterF)

            rehearsals = RehearsalScheduling.sorted(list)
            catalog = cat.map(\.song)
            roster = ros
            if selectedId == nil || !rehearsals.contains(where: { $0.id == selectedId }) {
                await select(RehearsalScheduling.defaultRehearsalId(rehearsals))
            }
        } catch let apiError as APIError {
            error = apiError
        } catch let other {
            error = .transport(other.localizedDescription)
        }
        isLoading = false
    }

    public func select(_ id: Int?) async {
        selectedId = id
        detail = nil
        if let id { await loadDetail(id) }
    }

    private func loadDetail(_ id: Int) async {
        detailLoading = true
        do {
            detail = try await api.send(.rehearsalDetail(bandId: bandId, id: id))
        } catch let apiError as APIError {
            error = apiError
        } catch let other {
            error = .transport(other.localizedDescription)
        }
        detailLoading = false
    }

    public func selectPrevious() async {
        guard let i = selectedIndex, i > 0 else { return }
        await select(rehearsals[i - 1].id)
    }

    public func selectNext() async {
        guard let i = selectedIndex, i < rehearsals.count - 1 else { return }
        await select(rehearsals[i + 1].id)
    }

    // MARK: - Rehearsal lifecycle

    public func create(plannedAt: Date) async {
        formError = nil
        do {
            let created = try await api.send(.createRehearsal(bandId: bandId, .init(plannedAt: RehearsalScheduling.iso(from: plannedAt))))
            rehearsals = RehearsalScheduling.sorted(rehearsals + [created])
            await select(created.id)
        } catch let apiError as APIError {
            formError = apiError.userMessage
        } catch let other {
            formError = other.localizedDescription
        }
    }

    public func reschedule(_ rehearsalId: Int, plannedAt: Date) async {
        formError = nil
        do {
            let saved = try await api.send(.updateRehearsal(bandId: bandId, id: rehearsalId, .init(plannedAt: RehearsalScheduling.iso(from: plannedAt))))
            rehearsals = RehearsalScheduling.sorted(rehearsals.map { $0.id == saved.id ? saved : $0 })
            if detail?.id == saved.id {
                detail?.plannedAt = saved.plannedAt
                detail?.status = saved.status
            }
        } catch let apiError as APIError {
            formError = apiError.userMessage
        } catch let other {
            formError = other.localizedDescription
        }
    }

    public func delete(_ rehearsalId: Int) async {
        formError = nil
        do {
            _ = try await api.send(.deleteRehearsal(bandId: bandId, id: rehearsalId))
            rehearsals.removeAll { $0.id == rehearsalId }
            if selectedId == rehearsalId {
                await select(RehearsalScheduling.defaultRehearsalId(rehearsals))
            }
        } catch let apiError as APIError {
            formError = apiError.userMessage
        } catch let other {
            formError = other.localizedDescription
        }
    }

    /// Server-side clone: copies the source's songs (order/details), never its missing members.
    public func clone(sourceId: Int, plannedAt: Date?) async {
        formError = nil
        do {
            let created = try await api.send(.cloneRehearsal(bandId: bandId, id: sourceId, .init(plannedAt: plannedAt.map(RehearsalScheduling.iso))))
            rehearsals = RehearsalScheduling.sorted(rehearsals + [created.summary])
            selectedId = created.id
            detail = created
        } catch let apiError as APIError {
            formError = apiError.userMessage
        } catch let other {
            formError = other.localizedDescription
        }
    }

    // MARK: - Setlist

    public func addSong(songId: Int) async {
        guard let rehearsalId = selectedId else { return }
        guard !(detail?.songs ?? []).contains(where: { $0.songId == songId }) else { return }
        formError = nil
        do {
            let added = try await api.send(.addRehearsalSong(bandId: bandId, rehearsalId: rehearsalId, .init(songId: songId)))
            detail?.songs.append(added)
        } catch let apiError as APIError {
            formError = apiError.userMessage
        } catch let other {
            formError = other.localizedDescription
        }
    }

    public func removeSong(rehearsalSongId: Int) async {
        guard let rehearsalId = selectedId else { return }
        guard (detail?.songs ?? []).contains(where: { $0.id == rehearsalSongId }) else { return }
        formError = nil
        do {
            _ = try await api.send(.removeRehearsalSong(bandId: bandId, rehearsalId: rehearsalId, songRowId: rehearsalSongId))
            detail?.songs.removeAll { $0.id == rehearsalSongId }
        } catch let apiError as APIError {
            formError = apiError.userMessage
        } catch let other {
            formError = other.localizedDescription
        }
    }

    /// Persist a drag-reorder. Only rows whose index changed get a PUT; applied optimistically,
    /// re-fetched on failure.
    public func reorder(_ newOrder: [RehearsalSong]) async {
        guard let rehearsalId = selectedId else { return }
        let current = detail?.songs ?? []
        let changed = newOrder.enumerated().filter { index, song in
            current.first { $0.id == song.id }?.ordering != index
        }
        guard !changed.isEmpty else { return }

        detail?.songs = newOrder.enumerated().map { index, song in
            var s = song; s.ordering = index; return s
        }
        formError = nil
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (index, song) in changed {
                    group.addTask {
                        _ = try await self.api.send(.updateRehearsalSong(
                            bandId: self.bandId, rehearsalId: rehearsalId, songRowId: song.id,
                            .init(songId: song.songId, ordering: index, details: song.details)
                        ))
                    }
                }
                try await group.waitForAll()
            }
        } catch let apiError as APIError {
            formError = apiError.userMessage
            await loadDetail(rehearsalId)
        } catch let other {
            formError = other.localizedDescription
            await loadDetail(rehearsalId)
        }
    }

    // MARK: - Missing members

    public func markMissing(bandMemberId: Int) async {
        guard let rehearsalId = selectedId else { return }
        guard !(detail?.missingMembers ?? []).contains(where: { $0.bandMemberId == bandMemberId }) else { return }
        formError = nil
        do {
            let added = try await api.send(.addMissingMember(bandId: bandId, rehearsalId: rehearsalId, .init(bandMemberId: bandMemberId)))
            detail?.missingMembers.append(added)
        } catch let apiError as APIError {
            formError = apiError.userMessage
        } catch let other {
            formError = other.localizedDescription
        }
    }

    public func markAttending(missingRowId: Int) async {
        guard let rehearsalId = selectedId else { return }
        guard (detail?.missingMembers ?? []).contains(where: { $0.id == missingRowId }) else { return }
        formError = nil
        do {
            _ = try await api.send(.removeMissingMember(bandId: bandId, rehearsalId: rehearsalId, rowId: missingRowId))
            detail?.missingMembers.removeAll { $0.id == missingRowId }
        } catch let apiError as APIError {
            formError = apiError.userMessage
        } catch let other {
            formError = other.localizedDescription
        }
    }
}
