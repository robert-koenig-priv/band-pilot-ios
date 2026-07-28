import SwiftUI
import BandPilotKit

/// Song edit/details sheet — all SongRequest fields plus the flag-assignment section.
/// Fields are read-only unless the user can edit songs (ADMIN/EDITOR); flag assignment is always
/// available (the backend only requires membership for it), matching the Android dialog.
struct SongEditSheet: View {
    let vm: BandDetailViewModel
    let song: Song
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var artist: String
    @State private var year: String
    @State private var ourKey: String
    @State private var origKey: String
    @State private var ourBpm: String
    @State private var origBpm: String
    @State private var duration: String
    @State private var comments: String
    @State private var status: SongStatus
    @State private var saving = false

    init(vm: BandDetailViewModel, song: Song) {
        self.vm = vm
        self.song = song
        _name = State(initialValue: song.name)
        _artist = State(initialValue: song.artist ?? "")
        _year = State(initialValue: song.year ?? "")
        _ourKey = State(initialValue: song.key ?? "")
        _origKey = State(initialValue: song.originalKey ?? "")
        _ourBpm = State(initialValue: song.bpm.map(String.init) ?? "")
        _origBpm = State(initialValue: song.originalBpm.map(String.init) ?? "")
        _duration = State(initialValue: DurationFormat.string(song.durationSec))
        _comments = State(initialValue: song.comments ?? "")
        _status = State(initialValue: song.status)
    }

    private var canEdit: Bool { vm.canEditSongs }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let formError = vm.formError { ErrorBanner(message: formError) }

                        LabeledField(label: "Name", text: $name, autocapitalization: .words)
                        LabeledField(label: "Artist", text: $artist, autocapitalization: .words)

                        VStack(alignment: .leading, spacing: 4) {
                            Kicker("Status")
                            Picker("Status", selection: $status) {
                                ForEach(SongStatus.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .disabled(!canEdit)
                        }

                        HStack(spacing: 10) {
                            LabeledField(label: "Our key", text: $ourKey)
                            LabeledField(label: "Original key", text: $origKey)
                        }
                        HStack(spacing: 10) {
                            LabeledField(label: "Our BPM", text: $ourBpm, keyboard: .numberPad)
                            LabeledField(label: "Original BPM", text: $origBpm, keyboard: .numberPad)
                        }
                        HStack(spacing: 10) {
                            LabeledField(label: "Year", text: $year, keyboard: .numberPad)
                            LabeledField(label: "Duration (m:ss)", text: $duration, keyboard: .numbersAndPunctuation)
                        }
                        LabeledField(label: "Comments", text: $comments, autocapitalization: .sentences)

                        FlagAssignmentSection(vm: vm, songId: song.id)
                    }
                    .padding(20)
                    .disabled(saving)
                }
            }
            .navigationTitle(song.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(canEdit ? "Cancel" : "Close") { dismiss() }
                }
                if canEdit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await save() } }
                            .disabled(name.isEmpty || artist.isEmpty || saving)
                    }
                }
            }
        }
        .tint(Palette.selected)
    }

    private func save() async {
        saving = true
        let request = SongRequest(
            name: name,
            artist: artist,
            year: year.nilIfEmpty,
            originalKey: origKey.nilIfEmpty,
            key: ourKey.nilIfEmpty,
            originalBpm: Int(origBpm),
            bpm: Int(ourBpm),
            durationSec: DurationFormat.seconds(duration),
            comments: comments.nilIfEmpty,
            status: status
        )
        let ok = await vm.updateSong(songId: song.id, request: request)
        saving = false
        if ok { dismiss() }
    }
}

/// The band's flag catalog as toggle chips; tapping assigns/removes the flag on this song (band-wide).
private struct FlagAssignmentSection: View {
    let vm: BandDetailViewModel
    let songId: Int

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 8)]

    var body: some View {
        if !vm.flagCatalog.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Kicker("Flags")
                if let flagError = vm.flagError {
                    Text(flagError).font(.footnote).foregroundStyle(Palette.danger)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(vm.flagCatalog) { flag in
                        flagChip(flag)
                    }
                }
            }
        }
    }

    private func flagChip(_ flag: Flag) -> some View {
        let assignment = (vm.flags[songId] ?? []).first { $0.flagId == flag.id }
        let selected = assignment != nil
        return Button {
            Task {
                if let assignment {
                    await vm.removeFlag(songId: songId, assignmentId: assignment.id)
                } else {
                    await vm.assignFlag(songId: songId, flagId: flag.id)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Circle().fill(Color(hexString: flag.color)).frame(width: 10, height: 10)
                Text(flag.meaning).font(.system(size: 14)).foregroundStyle(Palette.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selected ? Palette.selected.opacity(0.18) : Palette.bgSoft)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Palette.selected : Palette.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
