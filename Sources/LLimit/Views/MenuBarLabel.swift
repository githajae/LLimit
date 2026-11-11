import SwiftUI
import AppKit

/// The live status indicator in the system menu bar. Follows the main
/// account (or every account when none is chosen) and renders two stacked
/// bars plus an optional percent label. The bars are the account's first two
/// windows in popover order: Weekly over Fable for Claude, 5h over 7d for
/// Codex.
///
/// On macOS 26, MenuBarExtra no longer renders complex SwiftUI view
/// hierarchies (GeometryReader, ZStack, etc.) in its label. We work around
/// this by rasterising the bars into an NSImage and displaying it via
/// `Image(nsImage:)`.
struct MenuBarLabel: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var refresher: RefreshCoordinator

    @AppStorage("compactMenuBar") private var compactMenuBar: Bool = false
    @AppStorage(MenuBarAccount.storageKey) private var menuBarAccountID: String = ""

    var body: some View {
        let summary = highestLoad()
        HStack(spacing: 4) {
            Image(nsImage: BarsIconRenderer.render(
                short: summary.top,
                long: summary.bottom,
                color: summary.nsColor
            ))
            if !compactMenuBar, let pct = summary.headlinePercent {
                Text("\(pct)%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
            }
        }
    }

    private struct Summary {
        let top: Double?
        let bottom: Double?
        let headlinePercent: Int?
        let color: Color
        let nsColor: NSColor
    }

    private func highestLoad() -> Summary {
        let snapshots = MenuBarAccount.shown(in: store.accounts, selection: menuBarAccountID)
            .compactMap { account -> UsageSnapshot? in
                guard case .loaded(let snap) = refresher.states[account.id] ?? .idle else { return nil }
                return snap
            }
        let bars = MenuBarAccount.bars(for: snapshots)
        let headline = bars.mostUsed

        let pct = headline.map { Int(((1 - $0) * 100).rounded()) }
        let (swiftColor, nsColor): (Color, NSColor) = {
            guard let h = headline else { return (.primary, .labelColor) }
            if h >= 0.9 { return (.red, .systemRed) }
            if h >= 0.7 { return (.orange, .systemOrange) }
            return (.primary, .labelColor)
        }()
        return Summary(top: bars.top, bottom: bars.bottom,
                       headlinePercent: pct, color: swiftColor, nsColor: nsColor)
    }
}

/// The account the menu bar follows, stored as its UUID string. Empty, or
/// an account that no longer exists, means every account.
enum MenuBarAccount {
    static let storageKey = "menuBarAccountID"

    static func main(in accounts: [Account], selection: String) -> Account? {
        accounts.first { $0.id.uuidString == selection }
    }

    static func shown(in accounts: [Account], selection: String) -> [Account] {
        main(in: accounts, selection: selection).map { [$0] } ?? accounts
    }

    /// Used fractions for the two menu bar bars, each the highest across
    /// `snapshots`, plus the most used window of all. Per account the bars
    /// are its first two windows in popover order.
    static func bars(for snapshots: [UsageSnapshot]) -> (top: Double?, bottom: Double?, mostUsed: Double?) {
        var top: [Double] = []
        var bottom: [Double] = []
        var all: [Double] = []
        for snapshot in snapshots {
            let windows = snapshot.windows
            if let used = windows.first?.usedPercent { top.append(used) }
            if windows.count > 1, let used = windows[1].usedPercent { bottom.append(used) }
            all += windows.compactMap(\.usedPercent)
        }
        return (top.max(), bottom.max(), all.max())
    }
}

/// Rasterises the two-bar gauge into an NSImage so that MenuBarExtra can
/// display it reliably across all macOS versions, including macOS 26.
enum BarsIconRenderer {
    static func render(short: Double?, long: Double?, color: NSColor) -> NSImage {
        let width: CGFloat = 18
        let height: CGFloat = 14
        let barHeight: CGFloat = 4
        let gap: CGFloat = 3
        let totalH = barHeight * 2 + gap
        let topY = (height - totalH) / 2
        let cornerRadius: CGFloat = 1.5

        let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            func drawBar(y: CGFloat, value: Double?) {
                let v = CGFloat(max(0, min(1, value ?? 0)))
                // Background track
                let bgRect = NSRect(x: 0, y: y, width: width, height: barHeight)
                let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
                color.withAlphaComponent(0.25).setFill()
                bgPath.fill()
                // Filled portion
                let fgWidth = value == nil ? 0 : max(1, width * v)
                if fgWidth > 0 {
                    let fgRect = NSRect(x: 0, y: y, width: fgWidth, height: barHeight)
                    let fgPath = NSBezierPath(roundedRect: fgRect, xRadius: cornerRadius, yRadius: cornerRadius)
                    color.setFill()
                    fgPath.fill()
                }
            }
            drawBar(y: topY, value: short)
            drawBar(y: topY + barHeight + gap, value: long)
            return true
        }
        image.isTemplate = false
        return image
    }
}
