import XCTest
@testable import LLimit

final class ClaudeSummaryTests: XCTestCase {
    func testWeeklyUsesLeastRemainingAndRetainsItsReset() {
        let date = Date(timeIntervalSince1970: 1000)
        let snapshot = UsageSnapshot(fetchedAt: Date(), windows: [
            UsageWindow(label: "5h", usedPercent: 0.1),
            UsageWindow(label: "7d", usedPercent: 0.33),
            UsageWindow(label: "Weekly · Fable", usedPercent: 0.84, resetsAt: date)
        ])
        XCTAssertEqual(snapshot.claudeSummaryWindows.map(\.label), ["5h", "7d"])
        XCTAssertEqual(snapshot.claudeSummaryWindows.last?.usedPercent, 0.84)
        XCTAssertEqual(snapshot.claudeSummaryWindows.last?.resetsAt, date)
        XCTAssertEqual(snapshot.claudeWeeklyHelp, "Weekly remaining · All models 67% · Fable 16%")
        XCTAssertEqual(snapshot.windows.count, 3)
    }

    func testAllModelsCanBeLimitingWithZeroFableUsage() {
        let snapshot = UsageSnapshot(fetchedAt: Date(), windows: [
            UsageWindow(label: "7d", usedPercent: 0.58),
            UsageWindow(label: "Weekly · Fable", usedPercent: 0)
        ])
        XCTAssertEqual(snapshot.claudeSummaryWindows.last?.usedPercent, 0.58)
    }
}
