import XCTest
@testable import BandPilotKit

final class AuthEndpointTests: XCTestCase {
    func testForgotPasswordEndpointShape() {
        let endpoint = Endpoint<MessageResponse>.forgotPassword(ForgotPasswordRequest(email: "user@example.com"))
        XCTAssertEqual(endpoint.path, "api/auth/forgot-password")
        XCTAssertEqual(endpoint.method, .post)
        XCTAssertFalse(endpoint.requiresAuth)
    }
}
