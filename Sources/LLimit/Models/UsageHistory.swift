import Foundation

/// Weekly-limit history for one account, derived from `usage_log.jsonl`.
///
/// Series are the weekly windows only: "Weekly" (`7d`) plus each
/// model-scoped weekly limit, named after its model ("Fable"). Usage is in
/// percent of that series' own limit.
struct UsageHistory {
    struct Point: Hashable, Identifiable {
        let time: Date
        let series: String
        let used: Double
        let resetsAt: Date?
        var id: String { "\(series)|\(time.timeIntervalSince1970)" }
    }

    struct Bucket: Hashable, Identifiable {
        /// Start of the day, or start of the weekly window.
        let start: Date
        let series: String
        var used: Double
        var id: String { "\(series)|\(start.timeIntervalSince1970)" }
    }

    static let weekLength: TimeInterval = 7 * 24 * 60 * 60
    /// Successive `resets_at` values for the same window can differ by a
    /// second or so; anything past this is a new window.
    static let sameWindowTolerance: TimeInterval = 60 * 60

    let points: [Point]
    /// "Weekly" first, then scoped limits, most recently seen first, so a
    /// current limit (Fable) keeps the leading colors over a retired one
    /// (Sonnet). Colors are assigned by this order.
    let series: [String]

    init(records: [UsageLogRecord], accountID: UUID) {
        var points: [Point] = []
        var lastSeen: [String: Date] = [:]
        for record in records {
            guard let entry = record.accounts.first(where: { $0.id == accountID }),
                  let windows = entry.windows else { continue }
            let time = entry.fetchedAt ?? record.time
            for window in windows {
                guard let name = Self.seriesName(for: window.label), let used = window.usedPercent else { continue }
                if name != "Weekly" { lastSeen[name] = max(lastSeen[name] ?? .distantPast, time) }
                points.append(Point(time: time, series: name, used: used, resetsAt: window.resetsAt))
            }
        }
        self.points = points.sorted { $0.time < $1.time }
        let hasWeekly = points.contains { $0.series == "Weekly" }
        let scoped = lastSeen.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
        self.series = (hasWeekly ? ["Weekly"] : []) + scoped
    }

    /// Claude labels scoped limits "Weekly · Fable"; Codex labels its extra
    /// model limits "<name> 7d".
    static func seriesName(for label: String) -> String? {
        if label == "7d" { return "Weekly" }
        if label.hasPrefix("Weekly · ") { return String(label.dropFirst("Weekly · ".count)) }
        if label.hasSuffix(" 7d"), label.count > 3 { return String(label.dropLast(" 7d".count)) }
        return nil
    }

    func points(for series: String) -> [Point] {
        points.filter { $0.series == series }
    }

    /// The weekly window the newest reading belongs to.
    func currentWindow(now: Date = Date()) -> DateInterval {
        let reference = points(for: "Weekly").last ?? points.last
        let end = reference?.resetsAt ?? now
        return DateInterval(start: end.addingTimeInterval(-Self.weekLength), end: end)
    }

    /// Readings inside `window`, grouped by series.
    func trend(in window: DateInterval) -> [Point] {
        series.flatMap { name in
            points(for: name).filter { $0.time >= window.start && $0.time <= window.end }
        }
    }

    /// Usage added between consecutive readings, attributed to the later one.
    /// A new window (its `resets_at` moved) counts everything used in it so
    /// far; a drop inside the same window (a reset credit) adds nothing.
    func increments(for series: String) -> [(time: Date, windowEnd: Date?, amount: Double)] {
        let readings = points(for: series)
        guard let first = readings.first else { return [] }
        var result: [(time: Date, windowEnd: Date?, amount: Double)] = []
        // The first reading's usage happened before logging began; it only
        // counts toward its own window's total, never toward a day.
        result.append((first.time, first.resetsAt, first.used))
        for (previous, current) in zip(readings, readings.dropFirst()) {
            let newWindow: Bool
            if let before = previous.resetsAt, let after = current.resetsAt {
                newWindow = abs(after.timeIntervalSince(before)) > Self.sameWindowTolerance
            } else {
                newWindow = current.used < previous.used - 0.5
            }
            let amount = newWindow ? current.used : max(0, current.used - previous.used)
            result.append((current.time, current.resetsAt, amount))
        }
        return result
    }

    /// Usage per calendar day over the last `days` days, in percent of each
    /// series' weekly limit.
    func daily(days: Int, now: Date = Date(), calendar: Calendar = .current) -> [Bucket] {
        let today = calendar.startOfDay(for: now)
        guard let firstDay = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        var totals: [String: Bucket] = [:]
        for name in series {
            for (index, increment) in increments(for: name).enumerated() where index > 0 {
                let day = calendar.startOfDay(for: increment.time)
                guard day >= firstDay, increment.amount > 0 else { continue }
                let key = "\(name)|\(day.timeIntervalSince1970)"
                totals[key, default: Bucket(start: day, series: name, used: 0)].used += increment.amount
            }
        }
        return totals.values.sorted { ($0.start, seriesIndex($0.series)) < ($1.start, seriesIndex($1.series)) }
    }

    /// Total usage of each of the last `limit` weekly windows. A window's
    /// total is its first logged reading plus everything added after it, so
    /// usage given back by a reset credit is still counted.
    func weekly(limit: Int) -> [Bucket] {
        var totals: [String: Bucket] = [:]
        for name in series {
            for increment in increments(for: name) {
                guard let end = increment.windowEnd else { continue }
                let rounded = Date(timeIntervalSince1970: (end.timeIntervalSince1970 / 3600).rounded() * 3600)
                let start = rounded.addingTimeInterval(-Self.weekLength)
                let key = "\(name)|\(start.timeIntervalSince1970)"
                totals[key, default: Bucket(start: start, series: name, used: 0)].used += increment.amount
            }
        }
        let starts = Array(Set(totals.values.map(\.start))).sorted().suffix(limit)
        return totals.values
            .filter { starts.contains($0.start) }
            .sorted { ($0.start, seriesIndex($0.series)) < ($1.start, seriesIndex($1.series)) }
    }

    private func seriesIndex(_ name: String) -> Int {
        series.firstIndex(of: name) ?? series.count
    }
}
