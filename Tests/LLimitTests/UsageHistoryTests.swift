import XCTest
@testable import LLimit

final class UsageHistoryTests: XCTestCase {
    private let account = UUID()
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

    private func record(_ time: String, weekly: Double, fable: Double? = nil, resets: String) -> UsageLogRecord {
        var windows = [UsageLogRecord.Window(label: "5h", usedPercent: 50, resetsAt: nil),
                       UsageLogRecord.Window(label: "7d", usedPercent: weekly, resetsAt: date(resets))]
        if let fable {
            windows.append(.init(label: "Weekly · Fable", usedPercent: fable, resetsAt: date(resets).addingTimeInterval(-1)))
        }
        return UsageLogRecord(time: date(time), accounts: [
            .init(id: account, name: "Claude", provider: .claude, fetchedAt: date(time), windows: windows)
        ])
    }

    func testSeriesAreWeeklyThenScopedAndSkipFiveHour() {
        let history = UsageHistory(records: [record("2026-11-10T00:00:00Z", weekly: 10, fable: 1, resets: "2026-11-13T14:00:00Z")], accountID: account)
        XCTAssertEqual(history.series, ["Weekly", "Fable"])
        XCTAssertEqual(history.points.count, 2)
        XCTAssertEqual(UsageHistory.seriesName(for: "GPT-5.3-Codex-Spark 7d"), "GPT-5.3-Codex-Spark")
        XCTAssertNil(UsageHistory.seriesName(for: "5h"))
    }

    func testRecentScopedLimitsComeBeforeRetiredOnes() {
        let old = UsageLogRecord(time: date("2026-06-01T00:00:00Z"), accounts: [
            .init(id: account, name: "Claude", provider: .claude, windows: [
                .init(label: "7d", usedPercent: 5, resetsAt: date("2026-06-05T14:00:00Z")),
                .init(label: "Weekly · Sonnet", usedPercent: 1, resetsAt: date("2026-06-05T14:00:00Z")),
            ])
        ])
        let history = UsageHistory(records: [old, record("2026-11-10T00:00:00Z", weekly: 10, fable: 1, resets: "2026-11-13T14:00:00Z")], accountID: account)
        XCTAssertEqual(history.series, ["Weekly", "Fable", "Sonnet"])
    }

    func testDailyAndWeeklyTotalsAcrossAResetAndACredit() {
        let records = [
            record("2026-11-12T10:00:00Z", weekly: 80, resets: "2026-11-13T14:00:00Z"),  // first reading: no day credit
            record("2026-11-12T20:00:00Z", weekly: 90, resets: "2026-11-13T14:00:00Z"),  // +10 on Nov 12
            record("2026-11-13T10:00:00Z", weekly: 20, resets: "2026-11-13T14:00:00Z"),  // reset credit: +0
            record("2026-11-13T12:00:00Z", weekly: 25, resets: "2026-11-13T14:00:00Z"),  // +5 on Nov 13
            record("2026-11-13T16:00:00Z", weekly: 3, resets: "2026-11-20T14:00:00Z"),   // new window: +3 on Nov 13
            record("2026-11-14T09:00:00Z", weekly: 10, resets: "2026-11-20T14:00:00Z"),  // +7 on Nov 14
        ]
        let history = UsageHistory(records: records, accountID: account)

        let daily = history.daily(days: 7, now: date("2026-11-14T12:00:00Z"), calendar: calendar)
        XCTAssertEqual(daily.map(\.used), [10, 8, 7])
        XCTAssertEqual(daily.map(\.start), [date("2026-11-12T00:00:00Z"), date("2026-11-13T00:00:00Z"), date("2026-11-14T00:00:00Z")])

        let weekly = history.weekly(limit: 8)
        XCTAssertEqual(weekly.map(\.start), [date("2026-11-06T14:00:00Z"), date("2026-11-13T14:00:00Z")])
        XCTAssertEqual(weekly.map(\.used), [95, 10])  // 80 + 10 + 0 + 5, then 3 + 7

        XCTAssertEqual(history.currentWindow(), DateInterval(start: date("2026-11-13T14:00:00Z"), end: date("2026-11-20T14:00:00Z")))
        XCTAssertEqual(history.trend(in: history.currentWindow()).map(\.used), [3, 10])
    }

    func testScopedWindowJitterStaysInTheSameWeek() {
        let records = [
            record("2026-11-10T00:00:00Z", weekly: 10, fable: 1, resets: "2026-11-13T14:00:00Z"),
            record("2026-11-10T06:00:00Z", weekly: 12, fable: 4, resets: "2026-11-13T14:00:00Z"),
        ]
        let weekly = UsageHistory(records: records, accountID: account).weekly(limit: 8)
        XCTAssertEqual(weekly.map(\.series), ["Weekly", "Fable"])
        XCTAssertEqual(Set(weekly.map(\.start)).count, 1)
        XCTAssertEqual(weekly.map(\.used), [12, 4])
    }

    func testLogRecordRoundTripsAndSkipsStaleSnapshots() throws {
        let now = Date()
        let fresh = Account(name: "Grok", provider: .grok, configDir: "/tmp/g")
        let stale = Account(name: "Codex", provider: .codex, configDir: "/tmp/c")
        let failing = Account(name: "Claude", provider: .claude, configDir: "/tmp/a")
        let states: [UUID: UsageState] = [
            fresh.id: .loaded(UsageSnapshot(fetchedAt: now, windows: [UsageWindow(label: "7d", usedPercent: 0.1312, resetsAt: now)], note: "Build 11%")),
            stale.id: .loaded(UsageSnapshot(fetchedAt: now.addingTimeInterval(-30), windows: [])),
            failing.id: .error("HTTP 500"),
        ]
        let record = try XCTUnwrap(UsageLog.record(time: now, refreshStartedAt: now.addingTimeInterval(-5),
                                                   accounts: [fresh, stale, failing], states: states))
        XCTAssertEqual(record.accounts.map(\.name), ["Grok", "Claude"])
        XCTAssertEqual(record.accounts.first?.windows?.first?.usedPercent, 13.12)
        XCTAssertEqual(record.accounts.last?.error, "HTTP 500")

        let line = try UsageLog.encoder().encode(record)
        XCTAssertFalse(line.contains(0x0A))
        let decoded = try UsageLog.decoder().decode(UsageLogRecord.self, from: line)
        XCTAssertEqual(decoded.accounts.map(\.name), ["Grok", "Claude"])
    }
}
