import Foundation

/// Per-band authorization rules, mirroring the Android `BandDetailViewModel`.
public enum Permissions {
    public static func isAdmin(_ role: SecurityRole?) -> Bool {
        role == .admin || role == .globalAdmin
    }

    public static func canEditSongs(_ role: SecurityRole?) -> Bool {
        role == .admin || role == .editor
    }

    /// Upload, rename, retag and delete band media files.
    ///
    /// Deliberately wider than ``canEditSongs``, mirroring the backend's `canManageMediaFiles`: a plain
    /// MEMBER must be able to upload, or "the singer uploads her version of the lead sheet" — the case
    /// the owner tag exists for — is impossible. GUEST stays read-only.
    public static func canUploadMedia(_ role: SecurityRole?) -> Bool {
        role == .admin || role == .editor || role == .member || role == .globalAdmin
    }

    /// There is deliberately **no per-file permission**: the owner tag is a UI filter, not an ACL, so
    /// anyone who may upload may also delete. Deletes are soft and audited server-side, which is what
    /// makes that safe — not the client hiding the button.
    public static func canDeleteMediaFile(_ role: SecurityRole?) -> Bool { canUploadMedia(role) }

    /// Voting is self-only, except ADMINs (incl. GLOBAL_ADMIN) who may act for any member.
    public static func canVoteFor(memberId: Int, myBandMemberId: Int?, isAdmin: Bool) -> Bool {
        isAdmin || memberId == myBandMemberId
    }
}
