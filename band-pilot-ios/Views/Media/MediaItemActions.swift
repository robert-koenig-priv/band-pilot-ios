import SwiftUI
import BandPilotKit

/// What a member may do to one media link or file beyond opening it: change who it belongs to, and
/// delete it.
///
/// Offered **twice over**, which is deliberate rather than redundant:
///
/// - a **trailing swipe** for delete, which is the gesture every iOS user already knows on a list row;
/// - a **long-press context menu** carrying both actions, because a swipe cannot express "make this
///   mine" legibly and because the menu is where iOS users look for per-item actions.
///
/// Only two owner states are offered — "mine" and "the whole band's" — since those are the only two the
/// backend lets a plain member set. Tagging material for a *third* member is an editor's job and lives in
/// the web UI; offering it here would produce a 403 the member could not act on.
///
/// Deleting goes through the caller's confirmation rather than happening on the swipe, because for a link
/// it is permanent. See `MediaSheet`'s `confirmingLink` / `confirmingFile`.
private struct MediaItemActions: ViewModifier {
    let enabled: Bool
    let label: String
    let ownedByMe: Bool
    let canClaim: Bool
    let onSetOwner: (Int?) -> Void
    let myBandMemberId: Int?
    let onDeleteRequested: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                // `allowsFullSwipe: false` so a long swipe cannot delete without the row's button being
                // tapped — the confirmation is the point, and a full-swipe delete would skip past it.
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive, action: onDeleteRequested) {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    if ownedByMe {
                        Button {
                            onSetOwner(nil)
                        } label: {
                            Label("Make it the band's", systemImage: "person.3")
                        }
                    } else if canClaim {
                        Button {
                            onSetOwner(myBandMemberId)
                        } label: {
                            Label("Mark as mine", systemImage: "person")
                        }
                    }
                    Button(role: .destructive, action: onDeleteRequested) {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .accessibilityHint("Long press for options for \(label)")
        } else {
            content
        }
    }
}

extension View {
    /// See ``MediaItemActions``.
    func mediaItemActions(
        enabled: Bool,
        label: String,
        ownedByMe: Bool,
        canClaim: Bool,
        onSetOwner: @escaping (Int?) -> Void,
        myBandMemberId: Int?,
        onDeleteRequested: @escaping () -> Void
    ) -> some View {
        modifier(
            MediaItemActions(
                enabled: enabled,
                label: label,
                ownedByMe: ownedByMe,
                canClaim: canClaim,
                onSetOwner: onSetOwner,
                myBandMemberId: myBandMemberId,
                onDeleteRequested: onDeleteRequested
            )
        )
    }
}
