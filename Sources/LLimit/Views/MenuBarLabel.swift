import SwiftUI
import AppKit

/// The live status indicator in the system menu bar. Picks the most-loaded
/// window across all accounts and renders two stacked bars (5h / 7d) plus
/// an optional percent label.
///
/// On macOS 26, MenuBarExtra no longer renders complex SwiftUI view
/// hierarchies (GeometryReader, ZStack, etc.) in its label. We work around
/// this by rasterising the bars into an NSImage and displaying it via
/// `Image(nsImage:)`.
struct MenuBarLabel: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var refresher: RefreshCoordinator

    @AppStorage("compactMenuBar") private var compactMenuBar: Bool = false

    var body: some View {
        let summary = highestLoad()
        HStack(spacing: 4) {
            Image(nsImage: BarsIconRenderer.render(
                short: summary.fiveHour,
                long: summary.sevenDay,
                color: summary.nsColor
            ))
            if !compactMenuBar, let pct = summary.headlinePercent {
                Text("\(pct)%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
            }
        }
    }

    private struct Summary {
        let fiveHour: Double?
        let sevenDay: Double?
        let headlinePercent: Int?
        let color: Color
        let nsColor: NSColor
    }

    private func highestLoad() -> Summary {
        var best5: Double? = nil
        var best7: Double? = nil
        var headline: Double? = nil

        for account in store.accounts {
            guard case .loaded(let snap) = refresher.states[account.id] ?? .idle else {
                continue
            }
            for w in snap.windows {
                guard let p = w.usedPercent else { continue }
                let label = w.label.lowercased()
                if label.contains("5h") || label.contains("5-hour") {
                    if best5 == nil || p > best5! { best5 = p }
                } else if label.contains("7d") || label.contains("week") {
                    if best7 == nil || p > best7! { best7 = p }
                }
                if headline == nil || p > headline! { headline = p }
            }
        }

        let pct = headline.map { Int(((1 - $0) * 100).rounded()) }
        let (swiftColor, nsColor): (Color, NSColor) = {
            guard let h = headline else { return (.primary, .labelColor) }
            if h >= 0.9 { return (.red, .systemRed) }
            if h >= 0.7 { return (.orange, .systemOrange) }
            return (.primary, .labelColor)
        }()
        return Summary(fiveHour: best5, sevenDay: best7,
                       headlinePercent: pct, color: swiftColor, nsColor: nsColor)
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
