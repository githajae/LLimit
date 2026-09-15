import SwiftUI

/// Drawn-from-shapes provider marks. Avoids bundling third-party brand
/// assets (trademark + redistribution headaches) while still reading as
/// "Anthropic / OpenAI" instead of the previous generic SF Symbols.
struct ProviderIcon: View {
    let provider: Provider
    var size: CGFloat = 16

    var color: Color {
        switch provider {
        case .claude: return Color(red: 0.85, green: 0.51, blue: 0.34)
        case .codex:  return Color(red: 0.06, green: 0.65, blue: 0.52)
        case .cursor: return Color(red: 0.82, green: 0.84, blue: 0.88)
        }
    }

    var body: some View {
        Group {
            switch provider {
            case .claude: AnthropicMark()
            case .codex:  OpenAIKnot()
            case .cursor: CursorMark()
            }
        }
        .foregroundStyle(color)
        .frame(width: size, height: size)
    }
}

/// Rounded square badge with the provider mark centered inside.
struct ProviderBadge: View {
    let provider: Provider
    var size: CGFloat = 22
    var corner: CGFloat = 5

    private var tint: Color { ProviderIcon(provider: provider).color }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner)
                .fill(tint.opacity(0.16))
            ProviderIcon(provider: provider, size: size * 0.66)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Anthropic mark
//
// Anthropic's wordmark uses a 4-petal asterisk: four elongated, rounded
// strokes radiating at 45° increments. We approximate it with 4 capsules.
private struct AnthropicMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .frame(width: s * 0.18, height: s * 0.98)
                        .rotationEffect(.degrees(Double(i) * 45))
                }
            }
            .frame(width: s, height: s)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - OpenAI mark
//
// OpenAI's mark is a hexagonal woven knot — 3 interlocking elliptical
// rings at 60° offsets. Stroked (not filled) so it reads as a "knot".
private struct OpenAIKnot: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let lineW = max(1.1, s * 0.10)
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Ellipse()
                        .stroke(lineWidth: lineW)
                        .frame(width: s * 0.92, height: s * 0.36)
                        .rotationEffect(.degrees(Double(i) * 60))
                }
            }
            .frame(width: s, height: s)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct CursorMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            CursorCube()
                .fill(style: FillStyle(eoFill: true))
                .frame(width: s, height: s)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct CursorCube: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let ox = rect.midX - s / 2
        let oy = rect.midY - s / 2
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x / 24 * s, y: oy + y / 24 * s)
        }
        var path = Path()
        path.move(to: pt(12.00, 0.13))
        path.addLine(to: pt(1.89, 5.68))
        path.addLine(to: pt(1.47, 6.40))
        path.addLine(to: pt(1.47, 17.59))
        path.addLine(to: pt(1.89, 18.31))
        path.addLine(to: pt(11.50, 23.86))
        path.addLine(to: pt(12.50, 23.86))
        path.addLine(to: pt(22.11, 18.31))
        path.addLine(to: pt(22.53, 17.59))
        path.addLine(to: pt(22.53, 6.40))
        path.addLine(to: pt(22.11, 5.68))
        path.addLine(to: pt(12.50, 0.13))
        path.closeSubpath()
        path.move(to: pt(2.66, 6.34))
        path.addLine(to: pt(21.21, 6.34))
        path.addLine(to: pt(21.51, 6.85))
        path.addLine(to: pt(12.23, 22.92))
        path.addLine(to: pt(12.00, 22.86))
        path.addLine(to: pt(12.00, 12.34))
        path.addLine(to: pt(11.70, 11.83))
        path.addLine(to: pt(2.59, 6.57))
        path.closeSubpath()
        return path
    }
}

