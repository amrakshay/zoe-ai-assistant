// Usage: swift tools/pngstat.swift in.png [checker-out.png]
// Prints alpha histogram and, optionally, composites onto a checkerboard.
import AppKit
let a = CommandLine.arguments
let img = NSImage(contentsOfFile: a[1])!
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
let w = rep.pixelsWide, h = rep.pixelsHigh
var transparent = 0, opaque = 0, partial = 0, opaqueWhite = 0
for y in 0..<h { for x in 0..<w {
    let c = rep.colorAt(x: x, y: y)!
    let al = c.alphaComponent
    if al < 0.01 { transparent += 1 } else if al > 0.99 { opaque += 1
        if c.redComponent > 0.98 && c.greenComponent > 0.98 && c.blueComponent > 0.98 { opaqueWhite += 1 } } else { partial += 1 }
}}
let n = Double(w*h)
print("\(w)x\(h) transparent=\(String(format:"%.1f",Double(transparent)/n*100))% opaque=\(String(format:"%.1f",Double(opaque)/n*100))% (white \(String(format:"%.1f",Double(opaqueWhite)/n*100))%) partial=\(String(format:"%.1f",Double(partial)/n*100))%")
if a.count > 2 {
    let out = NSImage(size: NSSize(width: w, height: h))
    out.lockFocus()
    for y in stride(from: 0, to: h, by: 20) { for x in stride(from: 0, to: w, by: 20) {
        (((x+y)/20) % 2 == 0 ? NSColor(white: 0.75, alpha: 1) : NSColor(white: 0.95, alpha: 1)).setFill()
        NSRect(x: x, y: y, width: 20, height: 20).fill() } }
    rep.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
    out.unlockFocus()
    let r = NSBitmapImageRep(data: out.tiffRepresentation!)!
    try! r.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
}
