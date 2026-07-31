import SwiftUI
import BandPilotKit

struct SongRow: View {
    let vm: BandDetailViewModel
    let song: Song
    let isWide: Bool
    let isVotingOpen: Bool
    let state: SongsHeaderState
    let onToggleVoting: () -> Void
    let onEdit: () -> Void
    let onMedia: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onEdit) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.name)
                            .font(.system(size: 17))
                            .foregroundStyle(Palette.text)
                        if let second = secondLine {
                            Text(second).font(.subheadline).foregroundStyle(Palette.textDim)
                        }
                        if let third = keyAndBpm {
                            Text(third).font(.caption).foregroundStyle(Palette.textDim)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if state.flagsVisible {
                    FlagBadges(flags: vm.flags[song.id] ?? [], size: isWide ? 16 : 14)
                }

                if state.visibleDetails.contains(.media), vm.hasMedia(song.id) {
                    Button(action: onMedia) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: isWide ? 24 : 20))
                            .foregroundStyle(Palette.selected)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onToggleVoting) {
                    HStack(spacing: 8) {
                        if state.visibleDetails.contains(.status) {
                            StatusMark(status: song.status, size: isWide ? 18 : 15)
                        }
                        if state.ratingDisplay != .hidden {
                            AverageRating(average: shownRating, size: isWide ? 20 : 16)
                        }
                        Image(systemName: isVotingOpen ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(Palette.textDim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if isVotingOpen {
                VotingSection(vm: vm, song: song, isWide: isWide)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .task { await vm.ensureMediaLoaded(songId: song.id) }
    }

    /// Artist and duration share the second line, joined by " · " — as on Android.
    private var secondLine: String? {
        var parts: [String] = []
        if state.visibleDetails.contains(.artist), let a = song.artist, !a.isEmpty { parts.append(a) }
        if state.visibleDetails.contains(.duration), let secs = song.durationSec, secs > 0 {
            parts.append(DurationFormat.string(secs))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var keyAndBpm: String? {
        var parts: [String] = []
        if state.visibleDetails.contains(.key), let k = song.key ?? song.originalKey, !k.isEmpty {
            parts.append(k)
        }
        if state.visibleDetails.contains(.bpm), let bpm = song.bpm ?? song.originalBpm, bpm > 0 {
            parts.append("\(bpm) BPM")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Follows the Rating display chip: the band's average, or this member's own vote.
    private var shownRating: Double {
        guard state.ratingDisplay == .own, let me = vm.myBandMemberId else { return song.averageRating }
        return Double(vm.individualRating(songId: song.id, memberId: me))
    }
}

/// Small status glyph (colored) for the row.
struct StatusMark: View {
    let status: SongStatus
    var size: CGFloat = 15

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size))
            .foregroundStyle(StatusBadge.colors(status).fg)
    }

    private var symbol: String {
        switch status {
        case .readyForStage: return "checkmark.circle.fill"
        case .needPractice: return "wrench.and.screwdriver.fill"
        case .suggested: return "questionmark.circle"
        }
    }
}

/// Inline per-member voting, mirroring the Android voting section.
struct VotingSection: View {
    let vm: BandDetailViewModel
    let song: Song
    let isWide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker("Votes")
            if let voteError = vm.voteError {
                Text(voteError).font(.footnote).foregroundStyle(Palette.danger)
            }
            ForEach(vm.roster) { member in
                VoteRow(vm: vm, song: song, member: member, isWide: isWide)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.bgSoft)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct VoteRow: View {
    let vm: BandDetailViewModel
    let song: Song
    let member: BandMember
    let isWide: Bool

    private var myRating: Int { vm.individualRating(songId: song.id, memberId: member.id) }
    private var isVetoed: Bool { myRating == -1 }
    private var canVote: Bool {
        Permissions.canVoteFor(memberId: member.id, myBandMemberId: vm.myBandMemberId, isAdmin: vm.isAdmin)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(member.nickName)
                .foregroundStyle(Palette.text)
                .frame(width: isWide ? 120 : 92, alignment: .leading)
                .lineLimit(1)

            RatingStars(
                rating: isVetoed ? 0 : myRating,
                color: canVote ? Palette.accent2 : Palette.textDim,
                size: isWide ? 22 : 18,
                onSet: canVote ? { newValue in
                    Task { await vm.castVote(songId: song.id, memberId: member.id, rating: newValue) }
                } : nil
            )

            Spacer(minLength: 0)

            Button {
                Task { await vm.castVote(songId: song.id, memberId: member.id, rating: isVetoed ? 0 : -1) }
            } label: {
                Image(systemName: "nosign")
                    .font(.system(size: isWide ? 20 : 17))
                    .foregroundStyle(isVetoed ? Palette.danger : Palette.line)
            }
            .buttonStyle(.plain)
            .disabled(!canVote)
        }
    }
}
