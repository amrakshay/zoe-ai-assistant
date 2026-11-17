// Renders the app icon (Zoe's orb with two eyes on a dark rounded square) into an .iconset.
// Usage: swift make-icon.swift OUT.iconset
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.09   // macOS icon grid: artwork ~82% of the canvas
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let tile = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.13, blue: 0.27, alpha: 1),
               ending: NSColor(srgbRed: 0.07, green: 0.06, blue: 0.13, alpha: 1))!.draw(in: tile, angle: -90)
    // The orb (same colours as the idle character).
    let d = rect.width * 0.58
    let orb = NSRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d)
    NSGradient(starting: NSColor(srgbRed: 0.72, green: 0.62, blue: 1.00, alpha: 1),
               ending: NSColor(srgbRed: 0.42, green: 0.30, blue: 0.86, alpha: 1))!
        .draw(in: NSBezierPath(ovalIn: orb), relativeCenterPosition: NSPoint(x: -0.3, y: 0.4))
    // Eyes.
    NSColor.white.withAlphaComponent(0.95).setFill()
    let ew = d * 0.11, eh = d * 0.16
    for x in [0.36, 0.64] {
        let r = NSRect(x: orb.minX + d * x - ew / 2, y: orb.minY + d * 0.56 - eh / 2, width: ew, height: eh)
        NSBezierPath(roundedRect: r, xRadius: ew / 2, yRadius: ew / 2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
