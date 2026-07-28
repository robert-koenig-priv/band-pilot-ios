import Foundation

/// What a media file *is*, used for grouping in the UI.
///
/// Deliberately tolerant of values this build has never heard of. `MediaType` is a plain
/// `RawRepresentable` enum, so a new server value makes the whole list fail to decode and the panel
/// renders empty — a guaranteed field bug for a feature whose backend is still evolving. Capability
/// (can this be previewed, can this be played) is derived from `mimeType` instead: a photo of a chord
/// chart arrives as `.sheet` with `image/jpeg`, and a viewer switching on the kind would hand a JPEG to
/// PDFKit and draw a blank page.
public enum MediaFileKind: Sendable, Hashable, Codable, CaseIterable {
    case audio
    /// Readable and cacheable, but not uploadable: a 10 GB free tier holds roughly 50 videos, and
    /// Backblaze caps free egress at 3x stored data per day.
    case video
    /// Lead sheets and chord charts — often a PDF, often a photo of one.
    case sheet
    case image
    /// A kind added by a newer backend. Displayed, never silently dropped.
    case unknown(String)

    public static var allCases: [MediaFileKind] { [.audio, .video, .sheet, .image] }

    public var rawValue: String {
        switch self {
        case .audio: return "AUDIO"
        case .video: return "VIDEO"
        case .sheet: return "SHEET"
        case .image: return "IMAGE"
        case .unknown(let raw): return raw
        }
    }

    public init(rawValue: String) {
        switch rawValue.uppercased() {
        case "AUDIO": self = .audio
        case "VIDEO": self = .video
        case "SHEET": self = .sheet
        case "IMAGE": self = .image
        default: self = .unknown(rawValue)
        }
    }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var label: String {
        switch self {
        case .audio: return "Audio"
        case .video: return "Video"
        case .sheet: return "Lead sheets"
        case .image: return "Images"
        case .unknown(let raw): return raw.capitalized
        }
    }
}

public enum UploadState: String, Codable, Sendable, Hashable {
    case pending = "PENDING"
    case ready = "READY"
    case abandoned = "ABANDONED"
}

public enum TakedownState: String, Codable, Sendable, Hashable {
    case active = "ACTIVE"
    case disabledNotice = "DISABLED_NOTICE"
    case removed = "REMOVED"
}

/// A file stored in the band's own S3-compatible bucket.
///
/// Distinct from ``MediaLink``, which is only a URL. These are real bytes the app downloads, verifies
/// and caches for offline use.
public struct MediaFile: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let bandId: Int
    public let songId: Int?
    public let name: String
    public let kind: MediaFileKind
    public let mimeType: String
    public let sizeBytes: Int64
    /// Content digest, and the cache key. Nil would make the file uncacheable by content.
    public let sha256: String?
    /// **UI filtering tag only — there is no per-file permission.** Any member may set it to any member
    /// of the band, or leave it nil meaning the band owns the file. Every member may read and change
    /// every file. Do not treat this as an ACL.
    public let ownerBandMemberId: Int?
    public let uploadState: UploadState
    public let takedownState: TakedownState
    public let uploadedByUserId: Int
    /// Kept as a raw string, matching this codebase's deliberate choice not to give the shared decoder a
    /// date strategy (see `Rehearsal.plannedAt`). Parse with ``ISO8601`` where a `Date` is needed.
    public let uploadedAt: String?
    public let createdAt: String
    public let deletedAt: String?
    /// The one "can I fetch this" flag to trust: the backend derives it from upload state, deletion and
    /// takedown state together, so no client re-combines those three axes.
    public let downloadable: Bool

    /// Which viewer can show this, decided by mime type rather than ``kind`` — see ``MediaFileKind``.
    public var viewer: MediaViewerKind {
        let mime = mimeType.lowercased()
        if mime == "application/pdf" { return .pdf }
        if mime.hasPrefix("image/") { return .image }
        if mime.hasPrefix("audio/") { return .audio }
        if mime.hasPrefix("video/") { return .video }
        return .unsupported
    }
}

public enum MediaViewerKind: Sendable, Hashable {
    case pdf, image, audio, video, unsupported
}

/// What the client must do to move bytes, deliberately not a bare URL.
///
/// For S3 the authentication is in the URL's query string and ``headers`` carries only what the request
/// must send anyway (`Content-Type`/`Content-MD5`, both signed, so altering or omitting one yields a
/// 403). A future Google Drive or OneDrive adapter would put an `Authorization` header here instead — so
/// apply ``headers`` verbatim and never branch on the provider.
public struct TransferEnvelope: Codable, Sendable, Hashable {
    public let method: String
    public let url: URL
    public let headers: [String: String]
    public let expiresAt: String

    public init(method: String, url: URL, headers: [String: String] = [:], expiresAt: String) {
        self.method = method
        self.url = url
        self.headers = headers
        self.expiresAt = expiresAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        method = try c.decode(String.self, forKey: .method)
        url = try c.decode(URL.self, forKey: .url)
        // absent for S3, present for a future header-authenticated provider
        headers = try c.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        expiresAt = try c.decode(String.self, forKey: .expiresAt)
    }

    /// Whether this is still worth using.
    ///
    /// Presigned URLs are reused for their whole window on purpose: refetching one per file means a
    /// round trip to an instance that sleeps after 15 minutes and takes 30-60s to wake. The margin
    /// retires an envelope slightly early so a transfer cannot start moments before its URL dies, and an
    /// unparseable timestamp counts as expired — guessing a credential is still valid is the wrong way
    /// to be wrong.
    public func isUsable(now: Date = Date(), margin: TimeInterval = 30) -> Bool {
        guard let expiry = ISO8601.date(from: expiresAt) else { return false }
        return expiry.timeIntervalSince(now) > margin
    }
}

public struct MediaFileUploadIntentRequest: Codable, Sendable {
    public let name: String
    public let kind: MediaFileKind
    public let mimeType: String
    public let sizeBytes: Int64
    public let contentMd5: String?
    public let sha256: String?
    public let songId: Int?
    public let ownerBandMemberId: Int?
    public let acceptTerms: Bool

    public init(
        name: String,
        kind: MediaFileKind,
        mimeType: String,
        sizeBytes: Int64,
        contentMd5: String? = nil,
        sha256: String? = nil,
        songId: Int? = nil,
        ownerBandMemberId: Int? = nil,
        acceptTerms: Bool = false
    ) {
        self.name = name
        self.kind = kind
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.contentMd5 = contentMd5
        self.sha256 = sha256
        self.songId = songId
        self.ownerBandMemberId = ownerBandMemberId
        self.acceptTerms = acceptTerms
    }
}

public struct MediaFileUploadIntent: Codable, Sendable {
    public let file: MediaFile
    public let upload: TransferEnvelope
    /// An existing ready file with the same bytes — advice for the UI, not a refusal.
    public let duplicateOfId: Int?
}

/// What a client needs before it can honestly offer an upload button.
public struct MediaUploadPolicy: Codable, Sendable {
    public let storageConfigured: Bool
    public let canUpload: Bool
    public let requiresTermsAcceptance: Bool
    public let termsVersion: String
    public let videoUploadEnabled: Bool
    /// Browser-only concern (CORS); irrelevant here, but decoded so the shape matches the backend.
    public let webUploadSupported: Bool
    public let maxBytesByKind: [String: Int64]

    public func maxBytes(for kind: MediaFileKind) -> Int64? { maxBytesByKind[kind.rawValue] }
}

/// Whose files the panel shows.
///
/// ``mineAndBand`` means "owned by me **plus** the band's own files" — it never hides band-level
/// material, only another member's personal variant. A login with no roster entry has no "mine", so the
/// UI shows everyone's rather than an inexplicably short list.
public enum MediaOwnerFilter: Sendable, CaseIterable {
    case mineAndBand
    case everyone

    public var label: String {
        switch self {
        case .mineAndBand: return "Mine"
        case .everyone: return "Everyone"
        }
    }

    public func includes(_ file: MediaFile, myBandMemberId: Int?) -> Bool {
        switch self {
        case .everyone: return true
        case .mineAndBand:
            guard let mine = myBandMemberId else { return true }
            return file.ownerBandMemberId == nil || file.ownerBandMemberId == mine
        }
    }
}
