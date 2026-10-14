import XCTest
@testable import LLimit

final class ClaudeResetTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-04T03:00:00Z")!

    private func decode(_ json: String) throws -> AnthropicUsageAPI.RateLimits {
        try JSONDecoder().decode(AnthropicUsageAPI.RateLimits.self, from: Data(json.utf8))
    }

    func testGrantCountAndExpirationUseSharedResetModel() throws {
        let result = try decode(#"{"five_hour":{"utilization":93},"cedar_ember":{"eligible":true,"grants":[{"id":"launch","resets_left":2,"ends_at":"2026-10-22T16:00:00+00:00","usable_now":false,"use_requires_limit":true}]}}"#)
        let credits = try XCTUnwrap(result.cedarEmber?.resetCredits(now: now))
        XCTAssertEqual(credits.availableCount, 2)
        XCTAssertEqual(Set(credits.available.map(\.id)).count, 2)
        XCTAssertEqual(credits.earliestExpiration, ISO8601DateFormatter().date(from: "2026-10-22T16:00:00Z"))
        XCTAssertEqual(result.windows.first?.usedPercent, 0.93)
    }

    func testInactiveGrantsAreExcluded() throws {
        let result = try decode(#"{"cedar_ember":{"eligible":true,"grants":[{"id":"expired","resets_left":1,"ends_at":"2026-10-04T03:00:00Z"},{"id":"paused","resets_left":1,"paused":true},{"id":"future","resets_left":1,"starts_at":"2026-11-01T00:00:00Z"},{"id":"spent","resets_left":0},{"id":"active","resets_left":1}]}}"#)
        let credits = result.cedarEmber?.resetCredits(now: now)
        XCTAssertEqual(credits?.availableCount, 1)
        XCTAssertEqual(credits?.available.first?.id, "active-0")
    }

    func testUnknownOrMalformedResetDataPreservesUsage() throws {
        for block in ["null", #"{"eligible":false,"grants":[]}"#, #"{"eligible":true,"grants":"unexpected"}"#] {
            let result = try decode("{\"five_hour\":{\"utilization\":20},\"cedar_ember\":\(block)}")
            XCTAssertNil(result.cedarEmber?.resetCredits(now: now))
            XCTAssertEqual(result.windows.first?.usedPercent, 0.2)
        }
        XCTAssertNil(try decode("{}").cedarEmber)
    }

    func testEligibleEmptyGrantsMeansZero() throws {
        let result = try decode(#"{"cedar_ember":{"eligible":true,"grants":[]}}"#)
        XCTAssertEqual(result.cedarEmber?.resetCredits(now: now)?.availableCount, 0)
    }
}
