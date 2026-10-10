import XCTest
@testable import LLimit

@MainActor
final class CodexLoginFallbackTests: XCTestCase {
    func testBusyCallbackPortUsesDeviceAuthorization() {
        XCTAssertEqual(
            CLILoginRunner.codexLoginArguments(callbackPortAvailable: false),
            ["-c", "cli_auth_credentials_store=\"file\"", "login", "--device-auth"]
        )
    }

    func testAvailableCallbackPortKeepsBrowserAuthorization() {
        XCTAssertEqual(
            CLILoginRunner.codexLoginArguments(callbackPortAvailable: true),
            ["-c", "cli_auth_credentials_store=\"file\"", "login"]
        )
    }

    func testDeviceAuthorizationDetailsIgnoreANSIEscapes() {
        let output = """
        1. Open this link in your browser
           \u{001B}[94mhttps://auth.openai.com/codex/device\u{001B}[0m
        2. Enter this one-time code
           \u{001B}[94mAB12-CD34E\u{001B}[0m
        """

        XCTAssertEqual(
            CLILoginRunner.deviceAuthorizationDetails(in: output),
            .init(
                url: URL(string: "https://auth.openai.com/codex/device")!,
                code: "AB12-CD34E"
            )
        )
    }
}
