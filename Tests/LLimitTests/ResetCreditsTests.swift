import XCTest
@testable import LLimit
final class ResetCreditsTests: XCTestCase {
    func testDatesAndAvailableCredits() throws {
        let json = #"{"available_count":2,"credits":[{"id":"a","status":"available","title":"Full reset","expires_at":"2026-10-29T18:59:59.661793Z"},{"id":"b","status":"available","expires_at":"2026-10-22T20:25:41Z"},{"id":"c","status":"redeemed","expires_at":"2026-10-01T00:00:00Z"}]}"#
        let value = try JSONDecoder().decode(ResetCredits.self, from: Data(json.utf8))
        XCTAssertEqual(value.availableCount, 2)
        XCTAssertEqual(value.available.count, 2)
        XCTAssertNotNil(value.available[0].expiration)
        XCTAssertEqual(value.earliestExpiration, ISO8601DateFormatter().date(from:"2026-10-22T20:25:41Z"))
    }
    func testLocalizedBackendTitleUsesEnglishResetTypeLabel() throws {
        let data = Data(#"{"available_count":1,"credits":[{"id":"a","status":"available","title":"전체 재설정","reset_type":"codex_rate_limits"}]}"#.utf8)
        let value = try JSONDecoder().decode(ResetCredits.self, from: data)
        XCTAssertEqual(value.available.first?.englishTitle, "Full reset")
    }
    func testZeroAndUnknownDetailsAreDistinct() throws {
        let decoder = JSONDecoder()
        let zero = try decoder.decode(ResetCredits.self, from: Data(#"{"available_count":0,"credits":[]}"#.utf8))
        let unknown = try decoder.decode(ResetCredits.self, from: Data(#"{"available_count":3}"#.utf8))
        XCTAssertEqual(zero.availableCount, 0)
        XCTAssertEqual(unknown.availableCount, 3)
        XCTAssertNil(unknown.credits)
        XCTAssertNil(unknown.earliestExpiration)
    }
}
