import AppKit

// A simple LL monogram, drawn at every output size from the same geometry.
let output = CommandLine.arguments.dropFirst().first ?? "Resources/icon.png"
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let tile = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 200, yRadius: 200)
NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.21, blue: 0.25, alpha: 1),
           ending: NSColor(calibratedRed: 0.045, green: 0.085, blue: 0.12, alpha: 1))!.draw(in: tile, angle: -90)
func letter(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x, y: y + height))
    path.line(to: NSPoint(x: x, y: y))
    path.line(to: NSPoint(x: x + width, y: y))
    path.lineWidth = 88
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    color.setStroke()
    path.stroke()
}
letter(x: 306, y: 355, width: 142, height: 310, color: NSColor(calibratedWhite: 0.96, alpha: 1))
letter(x: 575, y: 355, width: 142, height: 310, color: NSColor(calibratedRed: 0.28, green: 0.86, blue: 0.72, alpha: 1))
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
