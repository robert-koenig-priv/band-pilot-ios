import Foundation

/// Backend `SongStatus`. Raw values match the JSON exactly.
public enum SongStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case suggested = "SUGGESTED"
    case needPractice = "NEED_PRACTICE"
    case readyForStage = "READY_FOR_STAGE"

    /// Human label, matching the Android app's `songStatusLabel()`.
    public var label: String {
        switch self {
        case .suggested: return "Suggested"
        case .needPractice: return "Need practice"
        case .readyForStage: return "Ready for stage"
        }
    }

    /// Practice-order rank: NEED_PRACTICE → SUGGESTED → READY_FOR_STAGE.
    public var practiceRank: Int {
        switch self {
        case .needPractice: return 0
        case .suggested: return 1
        case .readyForStage: return 2
        }
    }
}

/// Backend `SecurityRole`, per band membership. Raw values match the JSON exactly.
public enum SecurityRole: String, Codable, Sendable, Hashable {
    case globalAdmin = "GLOBAL_ADMIN"
    case admin = "ADMIN"
    case editor = "EDITOR"
    case member = "MEMBER"
    case guest = "GUEST"
}
