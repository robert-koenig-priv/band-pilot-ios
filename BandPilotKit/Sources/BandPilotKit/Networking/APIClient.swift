import Foundation

/// Thin async networking client over URLSession. One instance per app, shared via the SwiftUI
/// environment. Attaches the bearer token for non-auth calls and maps failures to `APIError`.
public actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    // Field names map by-name (camelCase already), so no key strategy is needed.
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private weak var tokenProvider: (any TokenProviding)?

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func setTokenProvider(_ provider: any TokenProviding) {
        self.tokenProvider = provider
    }

    public func send<R>(_ endpoint: Endpoint<R>) async throws -> R {
        var request = URLRequest(url: baseURL.appending(path: endpoint.path))
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if endpoint.requiresAuth, let token = await tokenProvider?.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = endpoint.body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost, .timedOut,
                 .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed:
                throw APIError.backendWaking
            default:
                throw APIError.transport(urlError.localizedDescription)
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("No HTTP response.")
        }

        switch http.statusCode {
        case 200...299:
            if R.self == EmptyResponse.self { return EmptyResponse() as! R }
            do {
                return try decoder.decode(R.self, from: data)
            } catch {
                throw APIError.decoding(String(describing: error))
            }
        case 401 where endpoint.requiresAuth:
            await tokenProvider?.handleUnauthorized()
            throw APIError.unauthorized
        case 500...599:
            throw APIError.backendWaking
        default:
            let problem = try? decoder.decode(ProblemDetails.self, from: data)
            throw APIError.http(status: http.statusCode, message: problem?.message, error: problem?.error)
        }
    }
}
