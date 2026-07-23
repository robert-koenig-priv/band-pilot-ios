import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

/// Mirrors the Android `userMessage()` error mapping.
public enum APIError: Error, Sendable, Equatable {
    /// 401 on a non-auth call → the caller clears the session and returns to login.
    case unauthorized
    /// Connection failure or 5xx — the Render free tier sleeps; show a friendly note + auto-retry.
    case backendWaking
    /// Any other non-2xx, with the decoded `{message,error}` body if present.
    case http(status: Int, message: String?, error: String?)
    case decoding(String)
    case transport(String)

    public var userMessage: String {
        switch self {
        case .unauthorized:
            return "Your session expired. Please sign in again."
        case .backendWaking:
            return "Data Backend available in 1-2 min."
        case let .http(status, message, error):
            return message ?? error ?? "Request failed (\(status))."
        case .decoding:
            return "Unexpected response from the server."
        case let .transport(message):
            return message
        }
    }

    /// True while the backend is (probably) still waking up, so the caller can schedule a retry.
    public var isBackendWaking: Bool {
        if case .backendWaking = self { return true }
        return false
    }
}

/// The backend's error body shape (`{message, error}`).
struct ProblemDetails: Decodable {
    let message: String?
    let error: String?
}
