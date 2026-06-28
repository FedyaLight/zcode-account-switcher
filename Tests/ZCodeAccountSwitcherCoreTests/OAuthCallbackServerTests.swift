import XCTest
@testable import ZCodeAccountSwitcherCore

final class OAuthCallbackServerTests: XCTestCase {
    func testOAuthCallbackServerReceivesBrowserCallback() async throws {
        let server = try await OAuthCallbackServer.start()
        defer { server.stop() }

        async let callback = server.waitForCallback(timeoutSeconds: 5)
        try await Task.sleep(nanoseconds: 100_000_000)
        let response = TestSupport.shell(["/usr/bin/curl", "-fsS", "\(server.redirectURI)?code=test-code&state=test-state"])

        XCTAssertTrue(response.contains("Login complete"))
        let callbackURL = try await callback
        let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "code" })?.value, "test-code")
        XCTAssertEqual(components?.queryItems?.first(where: { $0.name == "state" })?.value, "test-state")
    }
}
