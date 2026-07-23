import Foundation

/// Per-band authorization rules, mirroring the Android `BandDetailViewModel`.
public enum Permissions {
    public static func isAdmin(_ role: SecurityRole?) -> Bool {
        role == .admin || role == .globalAdmin
    }

    public static func canEditSongs(_ role: SecurityRole?) -> Bool {
        role == .admin || role == .editor
    }

    /// Voting is self-only, except ADMINs (incl. GLOBAL_ADMIN) who may act for any member.
    public static func canVoteFor(memberId: Int, myBandMemberId: Int?, isAdmin: Bool) -> Bool {
        isAdmin || memberId == myBandMemberId
    }
}
