import SwiftUI
import AppKit
import Charts

// MARK: - Window

/// Shows the dashboard in its own window. It stays open until the user
/// closes it, independent of the menu-bar popover.
@MainActor
final class DashboardWindowController {
    static let shared = DashboardWindowController()
    private var window: NSWindow?

    func show(store: AccountStore, refresher: RefreshCoordinator) {
        if window == nil {
            let root = DashboardView()
                .environmentObject(store)
                .environmentObject(refresher)
            let hosting = NSHostingController(rootView: root)
            hosting.sizingOptions = []
            let window = NSWindow(contentViewController: hosting)
            window.title = "LLimit Dashboard"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 1000, height: 820))
            window.minSize = NSSize(width: 760, height: 560)
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("LLimitDashboard")
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Palette

/// Series colors: the first three slots of the validated categorical
/// palette (blue, orange, aqua), stepped separately for light and dark.
/// Assigned in series order — "Weekly" first — never by rank.
enum SeriesPalette {
    private static let slots: [(light: UInt32, dark: UInt32)] = [
        (0x2a78d6, 0x3987e5),
        (0xeb6834, 0xd95926),
        (0x1baf7a, 0x199e70),
    ]

    static func color(at index: Int) -> Color {
        guard index < slots.count else { return .gray }
        let slot = slots[index]
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(rgb: dark ? slot.dark : slot.light)
        })
    }

    static func colors(for series: [String]) -> [Color] {
        series.indices.map(color(at:))
    }
}

private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xff) / 255,
                  green: CGFloat((rgb >> 8) & 0xff) / 255,
                  blue: CGFloat(rgb & 0xff) / 255, alpha: 1)
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var refresher: RefreshCoordinator
    @ObservedObject private var log = UsageLog.shared
    @State private var selection: UUID?

    var body: some View {
        NavigationSplitView {
            List(store.accounts, selection: $selection) { account in
                HStack(spacing: 10) {
                    ProviderBadge(provider: account.provider, size: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name).font(.body.weight(.medium))
                        Text(account.provider.displayName).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .tag(account.id)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            if !log.isLoaded {
                ProgressView("Loading history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let account = selectedAccount {
                AccountDashboard(
                    account: account,
                    history: UsageHistory(records: log.records, accountID: account.id),
                    readingCount: log.records.count,
                    loggingSince: log.records.first?.time,
                    refreshMinutes: store.pollIntervalSeconds / 60
                )
                .id(account.id)
            } else {
                Text("Add an account in Settings to see its history.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            log.loadIfNeeded()
            if selection == nil { selection = store.accounts.first?.id }
        }
    }

    private var selectedAccount: Account? {
        store.accounts.first { $0.id == selection } ?? store.accounts.first
    }
}

private struct AccountDashboard: View {
    let account: Account
    let history: UsageHistory
    let readingCount: Int
    let loggingSince: Date?
    let refreshMinutes: Int

    private let dailyDays = 14
    private let weeklyLimit = 8

    /// Series with data in `buckets`/`points`, in global order, with their
    /// fixed colors.
    private func present(_ names: some Sequence<String>) -> (series: [String], colors: [Color]) {
        let names = Set(names)
        let series = history.series.filter { names.contains($0) }
        return (series, series.map(color(for:)))
    }

    private func color(for series: String) -> Color {
        SeriesPalette.color(at: history.series.firstIndex(of: series) ?? history.series.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                if history.points.isEmpty {
                    Text("No readings for this account yet. LLimit logs every refresh (every \(refreshMinutes) min), so the charts fill in as readings arrive.")
                        .foregroundStyle(.secondary)
                } else {
                    let window = history.currentWindow()
                    DashboardSection(
                        title: "This week",
                        subtitle: "\(dayLabel(window.start)) – \(dayLabel(window.end)) · % of each limit used · dashed line is an even pace"
                    ) {
                        let trend = history.trend(in: window)
                        let shown = present(trend.map(\.series))
                        TrendChart(points: trend, series: shown.series, colors: shown.colors, window: window)
                    }
                    DashboardSection(
                        title: "Daily usage",
                        subtitle: "Last \(dailyDays) days · % of each weekly limit used that day · dashed line is 1/7 of the weekly limit"
                    ) {
                        let daily = history.daily(days: dailyDays)
                        let shown = present(daily.map(\.series))
                        DailyChart(buckets: daily, series: shown.series, colors: shown.colors, days: dailyDays)
                    }
                    DashboardSection(
                        title: "Weekly usage",
                        subtitle: "Last \(weeklyLimit) weekly windows · % of each limit used"
                    ) {
                        let weekly = history.weekly(limit: weeklyLimit)
                        let shown = present(weekly.map(\.series))
                        WeeklyChart(buckets: weekly, series: shown.series, colors: shown.colors)
                    }
                }
                footer
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ProviderBadge(provider: account.provider, size: 40, corner: 9)
            VStack(alignment: .leading, spacing: 4) {
                Text(account.name).font(.title2.weight(.semibold))
                Text(currentSummary).font(.body).foregroundStyle(.secondary)
            }
        }
    }

    /// "Weekly 34% used · Fable 4% used · resets in 3d 7h"
    private var currentSummary: String {
        let window = history.currentWindow()
        var parts = history.series.compactMap { name -> String? in
            guard let last = history.points(for: name).last, window.contains(last.time) else { return nil }
            return "\(name) \(Int(last.used.rounded()))% used"
        }
        if let end = history.points(for: "Weekly").last?.resetsAt, end > Date() {
            parts.append("resets in \(relative(end))")
        }
        return parts.isEmpty ? account.provider.displayName : parts.joined(separator: " · ")
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let loggingSince {
                Text("\(readingCount) readings logged since \(loggingSince.formatted(date: .abbreviated, time: .shortened))")
            } else {
                Text("No readings logged yet")
            }
            Spacer()
            Button("Reveal Log in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([UsageLog.fileURL])
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

private struct DashboardSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            content
        }
    }
}

// MARK: - Charts

private struct TrendChart: View {
    let points: [UsageHistory.Point]
    let series: [String]
    let colors: [Color]
    let window: DateInterval
    @State private var selected: Date?

    var body: some View {
        let ends = series.compactMap { name in points.last { $0.series == name } }
        Chart {
            ForEach([window.start, window.end], id: \.self) { date in
                LineMark(x: .value("Time", date), y: .value("Used", date == window.start ? 0 : 100),
                         series: .value("Series", "Even pace"))
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            ForEach(points) { point in
                LineMark(x: .value("Time", point.time), y: .value("Used", point.used),
                         series: .value("Series", point.series))
                    .foregroundStyle(by: .value("Limit", point.series))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .accessibilityLabel("\(point.series) \(point.time.formatted(date: .abbreviated, time: .shortened))")
                    .accessibilityValue("\(Int(point.used.rounded())) percent used")
            }
            // End dot (with a surface ring) and a direct value label.
            ForEach(ends) { point in
                PointMark(x: .value("Time", point.time), y: .value("Used", point.used))
                    .symbol {
                        Circle()
                            .fill(color(for: point.series))
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                    }
                PointMark(x: .value("Time", point.time), y: .value("Used", point.used))
                    .symbolSize(0)
                    .annotation(position: .trailing, alignment: .center, spacing: 8) {
                        Text("\(Int(point.used.rounded()))%")
                            .font(.callout.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                    }
            }
            if let selected, let readings = readings(near: selected, in: points) {
                RuleMark(x: .value("Time", readings.time))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Tooltip(title: readings.time.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()),
                                rows: readings.values.map { ($0.series, color(for: $0.series), "\(Int($0.used.rounded()))%") })
                    }
            }
        }
        .chartForegroundStyleScale(domain: series, range: colors)
        .chartXScale(domain: window.start...window.end)
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel(format: .dateTime.weekday(.abbreviated).day(), centered: false)
                    .font(.callout)
            }
        }
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%").font(.callout) }
            }
        }
        .chartLegend(position: .top, alignment: .leading, spacing: 10)
        .chartXSelection(value: $selected)
        .padding(.trailing, 36)
        .frame(height: 300)
    }

    private func color(for name: String) -> Color {
        series.firstIndex(of: name).map { colors[$0] } ?? .gray
    }

    /// Each series' reading nearest to `date`, snapped to the closest one.
    private func readings(near date: Date, in points: [UsageHistory.Point])
        -> (time: Date, values: [UsageHistory.Point])? {
        guard let anchor = points.min(by: { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) })
        else { return nil }
        let values = series.compactMap { name in
            points.filter { $0.series == name }
                .min { abs($0.time.timeIntervalSince(anchor.time)) < abs($1.time.timeIntervalSince(anchor.time)) }
        }
        return (anchor.time, values)
    }
}

private struct DailyChart: View {
    static let dailyShare = 100.0 / 7
    let buckets: [UsageHistory.Bucket]
    let series: [String]
    let colors: [Color]
    let days: Int
    @State private var selected: Date?

    private var range: ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let first = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return first...end
    }

    var body: some View {
        let selectedDay = selected.map { Calendar.current.startOfDay(for: $0) }
        VStack(alignment: .leading, spacing: 8) {
            SelectionReadout(
                title: selectedDay.map { $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) },
                rows: selectedDay.map { day in rows(buckets.filter { $0.start == day }) } ?? []
            )
            Chart {
                ForEach(buckets) { bucket in
                    BarMark(x: .value("Day", bucket.start, unit: .day), y: .value("Used", bucket.used), width: .fixed(12))
                        .foregroundStyle(by: .value("Limit", bucket.series))
                        // Bars of one day sit 2pt apart.
                        .position(by: .value("Limit", bucket.series), span: .fixed(CGFloat(14 * max(1, series.count))))
                        .cornerRadius(4)
                        .opacity(selectedDay == nil || selectedDay == bucket.start ? 1 : 0.35)
                        .accessibilityLabel("\(bucket.series) \(bucket.start.formatted(date: .abbreviated, time: .omitted))")
                        .accessibilityValue("\(Int(bucket.used.rounded())) percent of limit")
                }
                // An even share of the weekly limit per day; bars above it
                // used more than a day's worth.
                RuleMark(y: .value("Daily share", Self.dailyShare))
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("1/7 of weekly · \(Self.dailyShare.formatted(.number.precision(.fractionLength(1))))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            }
            .chartForegroundStyleScale(domain: series, range: colors)
            .chartXScale(domain: range)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true).font(.callout)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%").font(.callout) }
                }
            }
            .chartLegend(position: .top, alignment: .leading, spacing: 10)
            .chartXSelection(value: $selected)
            .frame(height: 230)
        }
    }

    private func rows(_ buckets: [UsageHistory.Bucket]) -> [(String, Color, String)] {
        series.enumerated().map { index, name in
            let used = buckets.first { $0.series == name }?.used ?? 0
            return (name, colors[index], "\(Int(used.rounded()))%")
        }
    }
}

private struct WeeklyChart: View {
    let buckets: [UsageHistory.Bucket]
    let series: [String]
    let colors: [Color]
    @State private var selected: String?

    private func label(_ start: Date) -> String {
        let end = start.addingTimeInterval(UsageHistory.weekLength)
        let sameMonth = Calendar.current.isDate(start, equalTo: end, toGranularity: .month)
        return "\(dayLabel(start))–" + (sameMonth ? end.formatted(.dateTime.day()) : dayLabel(end))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SelectionReadout(
                title: selected,
                rows: selected.map { week in rows(buckets.filter { label($0.start) == week }) } ?? []
            )
            Chart(buckets) { bucket in
                BarMark(x: .value("Week", label(bucket.start)), y: .value("Used", bucket.used), width: .fixed(22))
                    .foregroundStyle(by: .value("Limit", bucket.series))
                    // Bars of one week sit 2pt apart.
                    .position(by: .value("Limit", bucket.series), span: .fixed(CGFloat(24 * max(1, series.count))))
                    .cornerRadius(4)
                    .opacity(selected == nil || selected == label(bucket.start) ? 1 : 0.35)
                    .accessibilityLabel("\(bucket.series) week of \(label(bucket.start))")
                    .accessibilityValue("\(Int(bucket.used.rounded())) percent of limit")
            }
            .chartForegroundStyleScale(domain: series, range: colors)
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().font(.callout) }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%").font(.callout) }
                }
            }
            .chartLegend(position: .top, alignment: .leading, spacing: 10)
            .chartXSelection(value: $selected)
            .frame(height: 230)
        }
    }

    private func rows(_ buckets: [UsageHistory.Bucket]) -> [(String, Color, String)] {
        series.enumerated().map { index, name in
            let used = buckets.first { $0.series == name }?.used ?? 0
            return (name, colors[index], "\(Int(used.rounded()))%")
        }
    }
}

// MARK: - Pieces

/// Hover readout for bar charts; keeps its height when nothing is selected
/// so the chart below does not jump.
private struct SelectionReadout: View {
    let title: String?
    let rows: [(String, Color, String)]

    var body: some View {
        HStack(spacing: 14) {
            if let title {
                Text(title).font(.callout.weight(.semibold))
                ForEach(rows, id: \.0) { row in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(row.1).frame(width: 10, height: 10)
                        Text("\(row.0) \(row.2)").font(.callout.monospacedDigit())
                    }
                }
            } else {
                Text("Hover a bar for values").font(.callout).foregroundStyle(.tertiary)
            }
        }
        .frame(height: 20, alignment: .leading)
    }
}

private struct Tooltip: View {
    let title: String
    let rows: [(String, Color, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.semibold))
            ForEach(rows, id: \.0) { row in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(row.1).frame(width: 10, height: 10)
                    Text(row.0).font(.callout)
                    Spacer(minLength: 12)
                    Text(row.2).font(.callout.monospacedDigit().weight(.medium))
                }
            }
        }
        .padding(10)
        .frame(minWidth: 150)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
    }
}

private func dayLabel(_ date: Date) -> String {
    date.formatted(.dateTime.month(.abbreviated).day())
}

private func relative(_ date: Date) -> String {
    let seconds = Int(date.timeIntervalSinceNow)
    if seconds < 3600 { return "\(max(1, seconds / 60))m" }
    if seconds < 86400 { return "\(seconds / 3600)h \((seconds % 3600) / 60)m" }
    return "\(seconds / 86400)d \((seconds % 86400) / 3600)h"
}
