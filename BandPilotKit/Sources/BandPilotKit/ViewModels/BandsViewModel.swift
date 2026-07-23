import Foundation
import Observation

@MainActor
@Observable
public final class BandsViewModel {
    public private(set) var bands: [Band] = []
    public var isLoading = false
    public var error: APIError?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true
        error = nil
        do {
            bands = try await api.send(.bands)
        } catch let apiError as APIError {
            error = apiError
        } catch let other {
            error = .transport(other.localizedDescription)
        }
        isLoading = false
    }
}
