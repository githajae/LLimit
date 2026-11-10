import SwiftUI

/// Drawn-from-shapes provider marks. Avoids bundling third-party brand
/// assets (trademark + redistribution headaches) while still reading as
/// "Anthropic / OpenAI" instead of the previous generic SF Symbols.
struct ProviderIcon: View {
    let provider: Provider
    var size: CGFloat = 16

    var color: Color {
        switch provider {
        case .claude: return Color(red: 0.85, green: 0.51, blue: 0.34) // Anthropic clay/orange
        case .codex:  return Color(red: 0.06, green: 0.65, blue: 0.52) // OpenAI teal-green
        case .grok:   return Color(red: 0.45, green: 0.50, blue: 0.62) // neutral slate
        }
    }

    var body: some View {
        Group {
            switch provider {
            case .claude: AnthropicMark()
            case .codex:  OpenAIKnot()
            case .grok:   SlashMark()
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

// MARK: - Grok mark
//
// A generic slashed-circle glyph rather than xAI's logo: one ring with a
// diagonal stroke running through it.
private struct SlashMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let lineW = max(1.1, s * 0.11)
            ZStack {
                Circle()
                    .stroke(lineWidth: lineW)
                    .frame(width: s * 0.72, height: s * 0.72)
                Capsule()
                    .frame(width: lineW, height: s * 1.02)
                    .rotationEffect(.degrees(40))
            }
            .frame(width: s, height: s)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
