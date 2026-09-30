import XCTest
@testable import LLimit

final class AnthropicUsageTests: XCTestCase {
    func testNormalizedFableIncludesZeroUsageAndResetDateWithoutDuplicates() throws {
        let data = Data(#"{"five_hour":{"utilization":10,"resets_at":null},"seven_day":{"utilization":57,"resets_at":null},"limits":[{"kind":"session","percent":10},{"kind":"weekly_all","percent":57},{"kind":"weekly_scoped","percent":0,"resets_at":"2026-10-02T18:00:00+00:00","scope":{"model":{"display_name":"Fable"}}},{"kind":"future","percent":50}]}"#.utf8)
        let windows = try JSONDecoder().decode(AnthropicUsageAPI.RateLimits.self, from: data).windows
        XCTAssertEqual(windows.map(\.label), ["5h", "7d", "Weekly · Fable"])
        XCTAssertEqual(windows.last?.usedPercent, 0)
        XCTAssertNotNil(windows.last?.resetsAt)
    }

    func testLegacyResponseStillWorks() throws {
        let data = Data(#"{"five_hour":{"utilization":20,"resets_at":null},"seven_day_opus":{"utilization":0,"resets_at":null}}"#.utf8)
        let windows = try JSONDecoder().decode(AnthropicUsageAPI.RateLimits.self, from: data).windows
        XCTAssertEqual(windows.map(\.label), ["5h", "Weekly · Opus"])
        XCTAssertEqual(windows.first?.usedPercent, 0.2)
    }
}
