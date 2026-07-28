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
    /// Connection failure or 5xx — the backend could not be reached at all. Worth a retry, since the
    /// commonest causes are transient.
    ///
    /// The name is historical: it was coined when the backend ran on a free tier that slept when idle, so
    /// the message promised it back "in 1-2 min". It no longer sleeps, and the message no longer makes a
    /// promise it cannot keep.
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
            return "Data Backend currently not available"
        case let .http(status, message, error):
            return message ?? error ?? "Request failed (\(status))."
        case .decoding:
            return "Unexpected response from the server."
        case let .transport(message):
            return message
        }
    }

    /// True when the backend could not be reached, so the caller can offer or schedule a retry.
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
