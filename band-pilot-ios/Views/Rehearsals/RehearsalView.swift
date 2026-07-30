import SwiftUI
import BandPilotKit

struct RehearsalView: View {
    @State private var vm: RehearsalViewModel
    @State private var dateAction: RehearsalDateAction?
    let shell: ShellState

    init(bandId: Int, api: APIClient, shell: ShellState) {
        self.shell = shell
        _vm = State(wrappedValue: RehearsalViewModel(bandId: bandId, api: api))
    }

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            content
        }
        .navigationTitle("Rehearsals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) { actionsMenu }
        }
        .drawerToolbar(shell)
        .task { await vm.load() }
        .sheet(item: $dateAction) { action in
            DateTimeSheet(title: action.title, initial: initialDate(for: action)) { picked in
                Task { await perform(action, at: picked) }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if vm.isLoading && vm.rehearsals.isEmpty {
            ProgressView().tint(Palette.textDim)
        } else if let error = vm.error, vm.rehearsals.isEmpty {
            VStack(spacing: 12) {
                ErrorBanner(message: error.userMessage, waking: error.isBackendWaking)
                Button("Retry") { Task { await vm.load() } }.foregroundStyle(Palette.selected)
            }.padding(24)
        } else if vm.rehearsals.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                header
                if let formError = vm.formError {
                    ErrorBanner(message: formError).padding(.horizontal, 16).padding(.top, 8)
                }
                detailList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus").font(.system(size: 40)).foregroundStyle(Palette.textDim)
            Text("No rehearsals yet").foregroundStyle(Palette.textDim)
            PrimaryButton(title: "New rehearsal", fill: AnyShapeStyle(Palette.selected)) {
                dateAction = .create
            }
        }
    }

    // MARK: - Header (prev/next + date + status)

    private var header: some View {
        HStack(spacing: 12) {
            navButton("chevron.left", enabled: vm.hasPrevious) { await vm.selectPrevious() }
            VStack(spacing: 4) {
                if let detail = vm.detail {
                    Text(displayDate(detail.plannedAt)).font(.bebas(24)).foregroundStyle(Palette.text)
                    StatusPill(status: detail.status)
                } else {
                    Text("—").font(.bebas(24)).foregroundStyle(Palette.textDim)
                }
            }
            .frame(maxWidth: .infinity)
            navButton("chevron.right", enabled: vm.hasNext) { await vm.selectNext() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Palette.bgSoft)
    }

    private func navButton(_ symbol: String, enabled: Bool, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: symbol).font(.title3).foregroundStyle(enabled ? Palette.selected : Palette.line)
        }
        .disabled(!enabled)
    }

    private var actionsMenu: some View {
        Menu {
            Button { dateAction = .create } label: { Label("New rehearsal", systemImage: "plus") }
            if vm.detail != nil {
                Button { dateAction = .reschedule } label: { Label("Reschedule", systemImage: "clock.arrow.circlepath") }
                Button { dateAction = .clone } label: { Label("Clone", systemImage: "doc.on.doc") }
                Button(role: .destructive) {
                    if let id = vm.selectedId { Task { await vm.delete(id) } }
                } label: { Label("Delete", systemImage: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: - Detail (setlist / missing / add)

    private var detailList: some View {
        List {
            if vm.detailLoading && vm.detail == nil {
                ProgressView().tint(Palette.textDim).listRowBackground(Palette.bg)
            }

            Section {
                let songs = vm.detail?.songs ?? []
                if songs.isEmpty {
                    Text("No songs in this rehearsal yet.")
                        .foregroundStyle(Palette.textDim).italic()
                        .listRowBackground(Palette.bgCard)
                }
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    HStack(spacing: 10) {
                        Text("\(index + 1)").foregroundStyle(Palette.textDim).frame(width: 22, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.songName).foregroundStyle(Palette.text)
                            if let artist = song.artist, !artist.isEmpty {
                                Text(artist).font(.subheadline).foregroundStyle(Palette.textDim)
                            }
                        }
                    }
                    .listRowBackground(Palette.bgCard)
                }
                .onMove { indices, newOffset in
                    var reordered = vm.detail?.songs ?? []
                    reordered.move(fromOffsets: indices, toOffset: newOffset)
                    Task { await vm.reorder(reordered) }
                }
                .onDelete { indexSet in
                    let ids = indexSet.map { (vm.detail?.songs ?? [])[$0].id }
                    Task { for id in ids { await vm.removeSong(rehearsalSongId: id) } }
                }
            } header: {
                Text("Setlist").foregroundStyle(Palette.textDim)
            }

            Section {
                ForEach(vm.detail?.missingMembers ?? []) { member in
                    HStack {
                        Text(member.nickName).foregroundStyle(Palette.text)
                        Spacer()
                        Button { Task { await vm.markAttending(missingRowId: member.id) } } label: {
                            Image(systemName: "person.fill.checkmark").foregroundStyle(Palette.green)
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(Palette.bgCard)
                }
                if !vm.availableMembers.isEmpty {
                    Menu {
                        ForEach(vm.availableMembers) { member in
                            Button(member.nickName) { Task { await vm.markMissing(bandMemberId: member.id) } }
                        }
                    } label: {
                        Label("Mark someone missing", systemImage: "person.badge.minus").foregroundStyle(Palette.selected)
                    }
                    .listRowBackground(Palette.bgCard)
                }
            } header: {
                Text("Missing members").foregroundStyle(Palette.textDim)
            }

            Section {
                ForEach(vm.availableSongs) { song in
                    Button { Task { await vm.addSong(songId: song.id) } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill").foregroundStyle(Palette.selected)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.name).foregroundStyle(Palette.text)
                                if let artist = song.artist, !artist.isEmpty {
                                    Text(artist).font(.subheadline).foregroundStyle(Palette.textDim)
                                }
                            }
                        }
                    }
                    .listRowBackground(Palette.bgCard)
                }
            } header: {
                Text("Add songs").foregroundStyle(Palette.textDim)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
    }

    // MARK: - Helpers

    private func displayDate(_ iso: String) -> String {
        guard let date = RehearsalScheduling.date(from: iso) else { return iso }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func initialDate(for action: RehearsalDateAction) -> Date {
        switch action {
        case .create:
            return Date()
        case .reschedule, .clone:
            return vm.detail.flatMap { RehearsalScheduling.date(from: $0.plannedAt) } ?? Date()
        }
    }

    private func perform(_ action: RehearsalDateAction, at date: Date) async {
        switch action {
        case .create: await vm.create(plannedAt: date)
        case .reschedule: if let id = vm.selectedId { await vm.reschedule(id, plannedAt: date) }
        case .clone: if let id = vm.selectedId { await vm.clone(sourceId: id, plannedAt: date) }
        }
    }
}

enum RehearsalDateAction: Identifiable {
    case create, reschedule, clone
    var id: Int { hashValue }
    var title: String {
        switch self {
        case .create: return "New rehearsal"
        case .reschedule: return "Reschedule"
        case .clone: return "Clone rehearsal"
        }
    }
}

private struct StatusPill: View {
    let status: RehearsalStatus
    var body: some View {
        let color = status == .planned ? Palette.green : Palette.danger
        Text(status == .planned ? "Planned" : "Canceled")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

/// A date+time picker sheet returning the chosen Date.
struct DateTimeSheet: View {
    let title: String
    let onConfirm: (Date) -> Void
    @State private var date: Date
    @Environment(\.dismiss) private var dismiss

    init(title: String, initial: Date, onConfirm: @escaping (Date) -> Void) {
        self.title = title
        self.onConfirm = onConfirm
        _date = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bg.ignoresSafeArea()
                DatePicker("", selection: $date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(Palette.selected)
                    .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") { onConfirm(date); dismiss() }
                }
            }
        }
        .tint(Palette.selected)
    }
}
