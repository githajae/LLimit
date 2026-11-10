import XCTest
@testable import LLimit

final class FableResetTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-10T06:00:00Z")!

    /// Shape of the live response after the Fable launch: three Fable reset
    /// grants plus a Fable-scoped weekly limit.
    private let response = #"""
    {"seven_day":{"utilization":34.0,"resets_at":"2026-11-13T14:00:00.618848+00:00"},
     "limits":[
      {"kind":"weekly_all","percent":34,"resets_at":"2026-11-13T14:00:00.618848+00:00","scope":null,"is_active":true},
      {"kind":"weekly_scoped","percent":4,"resets_at":"2026-11-13T13:59:59.619065+00:00","scope":{"model":{"id":null,"display_name":"Fable"}},"is_active":false},
      {"kind":"weekly_scoped","percent":9,"resets_at":"2026-11-13T13:59:59.619065+00:00","scope":{"model":{"id":null,"display_name":"Fable"}},"is_active":true}],
     "cedar_ember":{"eligible":true,"grants":[
      {"id":"launch-2610-fable","label":"New model launch: one Fable reset for Max, Team Premium and Enterprise Premium","resets_left":1,"starts_at":"2026-11-09T18:00:00+00:00","ends_at":"2027-03-09T07:59:00+00:00","paused":false},
      {"id":"launch-2610-fable-12mo","label":"New model launch: one more Fable reset at 12 months' tenure","resets_left":1,"starts_at":"2026-11-09T18:00:00+00:00","ends_at":"2027-03-09T07:59:00+00:00","paused":false},
      {"id":"launch-2610-fable-6mo","label":"New model launch: one more Fable reset at 6 months' tenure","resets_left":1,"starts_at":"2026-11-09T18:00:00+00:00","ends_at":"2027-03-09T07:59:00+00:00","paused":false},
      {"id":"spring","label":"Spring usage reset","resets_left":1,"ends_at":"2027-04-01T00:00:00Z"}]}}
    """#

    private func decode() throws -> AnthropicUsageAPI.RateLimits {
        try JSONDecoder().decode(AnthropicUsageAPI.RateLimits.self, from: Data(response.utf8))
    }

    func testWeeklyAndFableBothShownOnce() throws {
        let limits = try decode()
        XCTAssertEqual(limits.windows.map(\.label), ["7d", "Weekly · Fable"])
        XCTAssertEqual(limits.windows.last?.usedPercent, 0.04)
        XCTAssertEqual(limits.scopedModelNames, ["Fable"])
    }

    func testFableGrantsAreNamedAndGrouped() throws {
        let limits = try decode()
        let credits = try XCTUnwrap(limits.cedarEmber?.resetCredits(now: now, modelNames: limits.scopedModelNames))
        XCTAssertEqual(credits.availableCount, 4)
        XCTAssertEqual(credits.available.filter { $0.englishTitle == "Fable reset" }.count, 3)

        let groups = credits.groups
        XCTAssertEqual(groups.map(\.title), ["Fable reset", "Usage reset"])
        XCTAssertEqual(groups.map(\.count), [3, 1])
        XCTAssertEqual(groups.first?.expiration, ISO8601DateFormatter().date(from: "2027-03-09T07:59:00Z"))
    }

    func testModelNameNeedsWholeWord() throws {
        let status = try JSONDecoder().decode(ClaudeResetStatus.self, from: Data(#"""
        {"eligible":true,"grants":[{"id":"a","label":"Fabled launch bonus","resets_left":1}]}
        """#.utf8))
        XCTAssertNil(status.resetCredits(now: now, modelNames: ["Fable"])?.available.first?.modelName)
    }
}
