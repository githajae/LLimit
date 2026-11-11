import SwiftUI
import AppKit

/// The popover is drawn 30% larger than upstream: every font size, bar,
/// ring, padding and width below goes through `S` / `Font.ll`.
private let uiScale: CGFloat = 1.3
private func S(_ value: CGFloat) -> CGFloat { value * uiScale }

private extension Font {
    /// System font at a macOS text-style point size, scaled by `uiScale`.
    static func ll(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: S(size), weight: weight, design: design)
    }
}

struct MenuContentView: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var refresher: RefreshCoordinator
    @Environment(\.openSettings) private var openSettings

    @AppStorage("popoverMode") private var popoverMode: PopoverMode = .summary
    @AppStorage(MenuBarAccount.storageKey) private var menuBarAccountID: String = ""

    enum PopoverMode: String, CaseIterable, Identifiable {
        case summary
        case detailed
        var id: String { rawValue }
        var systemImage: String {
            self == .summary ? "rectangle.compress.vertical" : "rectangle.expand.vertical"
        }
    }

    @State private var listHeight: CGFloat = 1
    @State private var screenHeight: CGFloat = NSScreen.main?.visibleFrame.height ?? 800
    private var maximumListHeight: CGFloat { max(S(120), min(S(700), screenHeight - 150)) }

    /// Summary is a little wider than upstream so a Claude row with 5h,
    /// weekly and a model-scoped limit still fits beside the reset counter.
    private var width: CGFloat { S(popoverMode == .summary ? 500 : 540) }

    var body: some View {
        VStack(alignment: .leading, spacing: S(0)) {
            header
            Divider().padding(.horizontal, S(16))

            if store.accounts.isEmpty {
                Text("No accounts. Open Settings to add one.")
                    .foregroundStyle(.secondary)
                    .font(.ll(12))
                    .padding(S(16))
            } else {
                ScrollView(.vertical) {
                VStack(spacing: S(8)) {
                    ForEach(store.accounts) { account in
                        let isMain = MenuBarAccount.main(in: store.accounts, selection: menuBarAccountID)?.id == account.id
                        Group {
                            if popoverMode == .summary {
                                AccountRowSummary(
                                    account: account,
                                    state: refresher.states[account.id] ?? .idle,
                                    isMain: isMain
                                )
                            } else {
                                AccountCardDetailed(
                                    account: account,
                                    state: refresher.states[account.id] ?? .idle,
                                    isMain: isMain
                                )
                            }
                        }
                        .contextMenu {
                            if isMain {
                                Button("Use All Accounts") { menuBarAccountID = "" }
                            } else {
                                Button("Make Main Account") { menuBarAccountID = account.id.uuidString }
                            }
                        }
                    }
                }
                .modifier(AlignedResetColumns())
                .padding(.horizontal, S(16))
                .padding(.vertical, S(12))
                .background(GeometryReader { proxy in
                    Color.clear
                        .onAppear { listHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, height in listHeight = height }
                })
                }
                .frame(height: min(listHeight, maximumListHeight))

            }

            Divider().padding(.horizontal, S(16))
            footer
        }
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        .background(MenuScreenReader { screenHeight = $0 })
    }

    private var header: some View {
        HStack(spacing: S(10)) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: S(24), height: S(24))
            Text("LLimit").font(.ll(13, .bold))
            Spacer()

            Picker("", selection: $popoverMode) {
                ForEach(PopoverMode.allCases) { m in
                    Image(systemName: m.systemImage).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: S(80))

            if let date = refresher.lastRefreshedAt {
                Text(date, style: .relative)
                    .font(.ll(10, .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, S(16))
        .padding(.top, S(14))
        .padding(.bottom, S(12))
    }

    private var footer: some View {
        HStack(spacing: S(12)) {
            Button {
                Task { await refresher.refreshAll() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            Button {
                DashboardWindowController.shared.show(store: store, refresher: refresher)
            } label: {
                Label("Dashboard", systemImage: "chart.xyaxis.line")
            }
            Spacer()
            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
        .buttonStyle(.borderless)
        .padding(.horizontal, S(16))
        .padding(.vertical, S(10))
    }
}

private struct MenuScreenReader: NSViewRepresentable {
    let update: (CGFloat) -> Void
    func makeNSView(context: Context) -> ScreenView { ScreenView(update: update) }
    func updateNSView(_ view: ScreenView, context: Context) { view.reportScreen() }

    final class ScreenView: NSView {
        let update: (CGFloat) -> Void
        init(update: @escaping (CGFloat) -> Void) { self.update = update; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let window {
                NotificationCenter.default.addObserver(self, selector: #selector(reportScreen),
                    name: NSWindow.didChangeScreenNotification, object: window)
            }
            reportScreen()
        }
        @objc func reportScreen() {
            guard let screen = window?.screen else { return }
            let height = screen.visibleFrame.height
            DispatchQueue.main.async { [weak self] in self?.update(height) }
        }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

// MARK: - Summary row (one line per account, every window inline)

private struct AccountRowSummary: View {
    let account: Account
    let state: UsageState
    var isMain = false

    var body: some View {
        HStack(spacing: S(10)) {
            providerBadge

            VStack(alignment: .leading, spacing: S(2)) {
                HStack(spacing: S(3)) {
                    Text(account.name)
                        .font(.ll(11, .semibold))
                        .lineLimit(1)
                    if isMain { MainAccountMark() }
                }
                if needsLoginToSeparate {
                    Text("sign in to separate accounts")
                        .font(.ll(10, .medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                } else if let id = identityLine {
                    Text(id)
                        .font(.ll(10, .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(width: identityWidth, alignment: .leading)

            // Inline mini-bars: one column per window, fills remaining space.
            stateContent

            Spacer(minLength: S(0))
        }
        .padding(.horizontal, S(12))
        .padding(.vertical, S(10))
        .background(
            RoundedRectangle(cornerRadius: S(8))
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: S(8))
                .stroke(Color.secondary.opacity(0.15), lineWidth: S(0.5))
        )
    }

    private var identityWidth: CGFloat {
        guard case .loaded(let snapshot) = state else { return S(150) }
        switch columnCount(snapshot) {
        case 4...: return S(110)
        case 3: return S(130)
        default: return S(150)
        }
    }

    private var providerBadge: some View {
        ProviderBadge(provider: account.provider, size: S(22))
    }

    private var showsResets: Bool {
        account.provider == .codex || account.provider == .claude
    }

    /// Usage bars plus the reset counter; three or more columns switch the
    /// bars to their compact form so the row keeps its width.
    private func columnCount(_ snapshot: UsageSnapshot) -> Int {
        snapshot.windows.count + (showsResets ? 1 : 0)
    }

    private var accent: Color {
        ProviderIcon(provider: account.provider).color
    }

    private var identityLine: String? {
        guard case .loaded(let snap) = state else { return nil }
        var parts: [String] = []
        if let e = snap.email { parts.append(e) }
        if let p = snap.planLabel { parts.append(p) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Claude accounts share a global keychain entry. Until the user signs
    /// in *through LLimit* (which writes a per-account snapshot), every
    /// Claude row sees whichever credential the CLI logged in last.
    private var needsLoginToSeparate: Bool {
        account.provider == .claude
            && !ClaudeAuthSource.hasSnapshot(for: account.id)
    }

    @ViewBuilder
    private var stateContent: some View {
        switch state {
        case .idle:
            Text("—").font(.ll(10)).foregroundStyle(.secondary)
        case .loading:
            HStack(spacing: S(6)) {
                ProgressView().controlSize(.small)
                Text("loading…").font(.ll(10)).foregroundStyle(.secondary)
            }
        case .loaded(let snap):
            if snap.windows.isEmpty {
                Text("no usage windows")
                    .font(.ll(10)).foregroundStyle(.secondary)
            } else {
                HStack(spacing: S(10)) {
                    HStack(spacing: S(12)) {
                        ForEach(snap.windows, id: \.label) { w in
                            MiniWindow(window: w, accent: accent, compact: columnCount(snap) >= 3)
                                .help(summaryHelp(for: w, note: snap.note))
                        }
                    }
                    .frame(maxWidth: .infinity)

                    if showsResets {
                        CompactResetCount(credits: snap.resetCredits, iconOnly: columnCount(snap) >= 4)
                    }
                }
            }
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.ll(10))
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    private func summaryHelp(for window: UsageWindow, note: String?) -> String {
        var text = "Remaining usage · " + window.label
        if let resets = window.resetsAt, resets > Date() { text += " · resets in \(formatRelative(resets))" }
        if let note, !note.isEmpty { text += "\n" + note }
        return text
    }
}

/// Marks the main account, which the menu bar icon and warnings follow.
private struct MainAccountMark: View {
    var body: some View {
        Image(systemName: "star.fill")
            .font(.ll(8, .semibold))
            .foregroundStyle(.yellow)
            .help("Main account: shown in the menu bar and warns")
            .accessibilityLabel("Main account")
    }
}

private struct CompactResetCount: View {
    let credits: ResetCredits?
    var iconOnly = false

    private var label: String {
        credits.map { "\($0.availableCount)" } ?? "—"
    }

    private var description: String {
        guard let credits else { return "Reset count unavailable" }
        let lines = credits.groups.map { group in
            "\(group.count)× \(group.title)" + (group.expiration.map { " · expires \(resetDateLabel($0))" } ?? "")
        }
        return (["\(credits.availableCount) resets available"] + lines).joined(separator: "\n")
    }

    var body: some View {
        HStack(spacing: S(5)) {
            if iconOnly {
                Image(systemName: "arrow.counterclockwise")
                    .font(.ll(9, .semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text("Resets")
                    .font(.ll(10, .medium))
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(.ll(10, .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(credits?.availableCount == 0 ? .tertiary : .secondary)
                .padding(.horizontal, S(5))
                .padding(.vertical, S(2))
                .background(Color.secondary.opacity(0.08), in: Capsule())
        }
        .fixedSize()
        .padding(.leading, S(10))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: S(0.5), height: S(20))
        }
        .help(description)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
    }
}

private struct MiniWindow: View {
    let window: UsageWindow
    let accent: Color
    var compact = false

    private var pct: Double {
        max(0, min(1, window.usedPercent ?? 0))
    }
    private var color: Color {
        if pct >= 0.9 { return .red }
        if pct >= 0.7 { return .orange }
        return accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: S(3)) {
            HStack(spacing: S(4)) {
                Text(shortLabel)
                    .font(.ll(10, .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: S(2))
                Text("\(Int(((1 - pct) * 100).rounded()))%" + (compact ? "" : " left"))
                    .font(Font.ll(10, .semibold).monospacedDigit())
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
            UsageBar(progress: pct, color: color)
                .frame(height: S(5))
        }
        .frame(minWidth: S(64), idealWidth: S(90))
    }

    /// Compact, fixed-width-ish labels so 4 windows fit on one row even on
    /// the summary view. `7d opus` is a model-specific weekly cap — drop the
    /// redundant `7D` prefix.
    private var shortLabel: String {
        if window.label.hasPrefix("Weekly · ") {
            return String(window.label.dropFirst("Weekly · ".count)).uppercased()
        }
        return window.label.uppercased()
    }
}

// MARK: - Detailed card (full bars + reset times + note)

private struct AccountCardDetailed: View {
    let account: Account
    let state: UsageState
    var isMain = false
    @Environment(\.resetColumnWidth) private var resetColumnWidth

    var body: some View {
        VStack(alignment: .leading, spacing: S(12)) {
            HStack(spacing: S(8)) {
                ProviderBadge(provider: account.provider, size: S(22))
                VStack(alignment: .leading, spacing: S(1)) {
                    HStack(spacing: S(3)) {
                        Text(account.name)
                            .font(.ll(11, .semibold))
                        if isMain { MainAccountMark() }
                    }
                    if needsLoginToSeparate {
                        Text("sign in to separate accounts")
                            .font(.ll(10, .medium))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    } else if let identity = identityLine {
                        Text(identity)
                            .font(.ll(10, .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                Text(account.provider.displayName.uppercased())
                    .font(.ll(10, .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
            }

            content
        }
        .padding(S(14))
        .background(
            RoundedRectangle(cornerRadius: S(8))
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: S(8))
                .stroke(Color.secondary.opacity(0.15), lineWidth: S(0.5))
        )
    }

    private var accent: Color {
        ProviderIcon(provider: account.provider).color
    }

    private var identityLine: String? {
        guard case .loaded(let snap) = state else { return nil }
        var parts: [String] = []
        if let e = snap.email { parts.append(e) }
        if let p = snap.planLabel { parts.append(p) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var needsLoginToSeparate: Bool {
        account.provider == .claude
            && !ClaudeAuthSource.hasSnapshot(for: account.id)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            Text("—").font(.ll(10)).foregroundStyle(.secondary)
        case .loading:
            HStack(spacing: S(6)) {
                ProgressView().controlSize(.small)
                Text("loading…").font(.ll(10)).foregroundStyle(.secondary)
            }
        case .loaded(let snap):
            HStack(alignment: .top, spacing: S(16)) {
                VStack(alignment: .leading, spacing: S(10)) {
                    if snap.windows.isEmpty {
                        Text("No usage in tracked windows")
                            .font(.ll(10)).foregroundStyle(.secondary)
                    } else {
                        ForEach(snap.windows, id: \.label) { w in
                            WindowRow(window: w, accent: accent)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if account.provider == .codex || account.provider == .claude {
                    ResetCreditsView(credits: snap.resetCredits)
                        .fixedSize(horizontal: true, vertical: false)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: ResetColumnWidthKey.self, value: proxy.size.width)
                        })
                        .frame(width: resetColumnWidth, alignment: .leading)
                        .frame(maxHeight: .infinity, alignment: .leading)
                        .padding(.leading, S(12))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color.secondary.opacity(0.15)).frame(width: S(1))
                        }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if let note = snap.note, !note.isEmpty {
                Text(note)
                    .font(.ll(10, .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.ll(10))
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }
}

private struct WindowRow: View {
    let window: UsageWindow
    let accent: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: S(12)) {
                VStack(alignment: .leading, spacing: S(4)) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(windowTitle)
                            .font(.ll(10, .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(rightText)
                            .font(Font.ll(10, .semibold).monospacedDigit())
                            .foregroundStyle(barColor)
                    }
                    UsageBar(progress: progress, color: barColor)
                        .frame(height: S(6))
                    HStack {
                        if let resets = window.resetsAt, resets > context.date {
                            Image(systemName: "clock")
                                .font(.ll(9))
                            Text("Resets in \(formatRelative(resets))")
                                .font(.ll(10, .medium))
                        }
                        Spacer()
                    }
                    .foregroundStyle(.tertiary)
                }

                if let resetProgress = resetProgress(at: context.date) {
                    ResetProgressRing(progress: resetProgress)
                }
            }
        }
    }

    /// Fraction of the current window that has elapsed, for windows with a
    /// known length.
    private func resetProgress(at now: Date) -> Double? {
        guard let resetsAt = window.resetsAt else { return nil }
        let duration: TimeInterval
        switch window.label {
        case "5h": duration = 5 * 60 * 60
        case "1d": duration = 24 * 60 * 60
        case "7d": duration = 7 * 24 * 60 * 60
        default:
            guard window.label.hasPrefix("Weekly · ") else { return nil }
            duration = 7 * 24 * 60 * 60
        }
        return max(0, min(1, 1 - resetsAt.timeIntervalSince(now) / duration))
    }

    /// Model-scoped weekly limits sit in the weekly grid beside "Weekly",
    /// so the model name alone is enough and fits next to the ring.
    private var windowTitle: String {
        switch window.label {
        case "5h": return "5-hour"
        case "7d": return "Weekly"
        default:
            if window.label.hasPrefix("Weekly · ") { return String(window.label.dropFirst("Weekly · ".count)) }
            return window.label
        }
    }

    private var progress: Double {
        if let p = window.usedPercent { return max(0, min(1, p)) }
        if let t = window.tokens {
            let cap = softCap(label: window.label)
            return min(1, Double(t) / cap)
        }
        return 0
    }

    private var rightText: String {
        if let p = window.usedPercent {
            return "\(Int(((1 - p) * 100).rounded()))% left"
        }
        if let t = window.tokens {
            return "\(formatTokens(t)) tok"
        }
        return ""
    }

    private var barColor: Color {
        let p = progress
        if p >= 0.9 { return .red }
        if p >= 0.7 { return .orange }
        return accent
    }

    private func softCap(label: String) -> Double {
        switch label {
        case "5h": return 2_000_000
        case "7d": return 25_000_000
        default: return 1_000_000
        }
    }
}

private struct ResetProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: S(4))
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.secondary.opacity(0.75),
                        style: StrokeStyle(lineWidth: S(4), lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: S(24), height: S(24))
        .help("\(Int((progress * 100).rounded()))% of this window has elapsed")
        .accessibilityLabel("Reset cycle progress")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
    }
}

private struct UsageBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: S(3))
                    .fill(Color.secondary.opacity(0.18))
                RoundedRectangle(cornerRadius: S(3))
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.85), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(progress > 0 ? S(4) : 0, geo.size.width * progress))
            }
        }
    }
}

private func formatRelative(_ date: Date) -> String {
    let secs = Int(date.timeIntervalSinceNow)
    if secs < 60 { return "<1m" }
    if secs < 3600 { return "\(secs / 60)m" }
    if secs < 86400 {
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }
    let d = secs / 86400
    let h = (secs % 86400) / 3600
    return h > 0 ? "\(d)d \(h)h" : "\(d)d"
}

// MARK: - Shared reset column width

/// Natural width of each card's reset column; the widest one wins.
private struct ResetColumnWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ResetColumnWidthEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

private extension EnvironmentValues {
    var resetColumnWidth: CGFloat? {
        get { self[ResetColumnWidthEnvironmentKey.self] }
        set { self[ResetColumnWidthEnvironmentKey.self] = newValue }
    }
}

/// Gives every detailed card's reset column the width of the widest one,
/// so the dividers line up from card to card.
struct AlignedResetColumns: ViewModifier {
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(ResetColumnWidthKey.self) { width = $0 }
            .environment(\.resetColumnWidth, width > 0 ? width : nil)
    }
}

private func resetDateLabel(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MMM d"
    return formatter.string(from: date)
}

/// Available resets grouped by kind and expiry, e.g. "3× Fable reset · Mar 9".
private struct ResetCreditsView: View {
    let credits: ResetCredits?
    @State private var showingAll = false

    private let inlineLimit = 2

    /// The column header already says "Resets", so rows drop the word:
    /// "3× Fable  Mar 9", "Full  Dec 1".
    private func shortTitle(_ group: ResetCredits.Group) -> String {
        let name = group.title.hasSuffix(" reset") ? String(group.title.dropLast(" reset".count)) : group.title
        return group.count > 1 ? "\(group.count)× \(name)" : name
    }

    private func row(_ group: ResetCredits.Group) -> some View {
        let expiry = group.expiration.map(resetDateLabel) ?? "—"
        let expiresSoon = (group.expiration?.timeIntervalSinceNow ?? .infinity) <= 3 * 86400
        let detail = "\(group.count)× \(group.title) · " + (group.expiration.map { "expires \(resetDateLabel($0))" } ?? "no expiry")
        return GridRow {
            Text(shortTitle(group))
                .lineLimit(1)
            Text(expiry)
                .monospacedDigit()
                .foregroundStyle(expiresSoon ? Color.orange : Color.secondary)
                .gridColumnAlignment(.trailing)
        }
        .font(.ll(10, .medium))
        .foregroundStyle(.secondary)
        .help(detail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail)
    }

    private func rows(_ groups: some Sequence<ResetCredits.Group>) -> some View {
        Grid(alignment: .leading, horizontalSpacing: S(8), verticalSpacing: S(4)) {
            ForEach(Array(groups)) { row($0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: S(6)) {
            HStack(spacing: S(5)) {
                Text("Resets").font(.ll(10, .medium))
                if let credits {
                    Text("\(credits.availableCount)")
                        .font(.ll(10, .medium, design: .rounded))
                        .padding(.horizontal, S(5)).padding(.vertical, S(1))
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                        .accessibilityLabel("\(credits.availableCount) resets available")
                }
            }.foregroundStyle(.secondary)
            if let credits {
                let groups = credits.groups
                if credits.availableCount == 0 {
                    Text("None available").font(.ll(10, .medium)).foregroundStyle(.secondary)
                } else if groups.isEmpty {
                    Text("Details unavailable").font(.ll(10, .medium)).foregroundStyle(.secondary)
                } else {
                    rows(groups.prefix(inlineLimit))
                    if groups.count > inlineLimit {
                        Button("+\(groups.count - inlineLimit) more…") { showingAll = true }
                            .buttonStyle(.plain)
                            .font(.ll(10, .medium)).foregroundStyle(.secondary)
                            .popover(isPresented: $showingAll) {
                                VStack(alignment: .leading, spacing: S(12)) {
                                    HStack {
                                        Text("Available resets").font(.ll(13, .bold))
                                        Spacer()
                                        Button { showingAll = false } label: {
                                            Image(systemName: "xmark")
                                        }.buttonStyle(.plain).accessibilityLabel("Close")
                                    }
                                    ScrollView {
                                        rows(groups)
                                    }.frame(maxHeight: S(220))
                                    if credits.availableCount > credits.available.count {
                                        Text("Some reset details are unavailable.")
                                            .font(.ll(10, .medium)).foregroundStyle(.secondary)
                                    }
                                }.padding(S(16)).frame(width: S(270))
                            }
                    }
                }
            } else {
                Text("Unavailable").font(.ll(10, .medium)).foregroundStyle(.secondary)
            }
        }
    }
}
