import Foundation

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// m:ss <-> seconds, for the song edit form's Duration field.
enum DurationFormat {
    static func string(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    static func seconds(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        let parts = trimmed.split(separator: ":")
        if parts.count == 2, let m = Int(parts[0]), let s = Int(parts[1]) { return m * 60 + s }
        return Int(trimmed)
    }
}
