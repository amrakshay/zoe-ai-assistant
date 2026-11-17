// Usage: swift tools/drag.swift x y dx dy   (global top-left coordinates, points)
// Posts a synthetic left-button drag. Needs Accessibility permission for the
// posting process; without it the events are silently dropped.
import CoreGraphics
import Foundation
let a = CommandLine.arguments.dropFirst().map { Double($0)! }
let (x, y, dx, dy) = (a[0], a[1], a[2], a[3])
print("AXIsProcessTrusted-equivalent check skipped; posting events")
func post(_ t: CGEventType, _ px: Double, _ py: Double) {
    CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: CGPoint(x: px, y: py), mouseButton: .left)!.post(tap: .cghidEventTap)
    usleep(30_000)
}
post(.mouseMoved, x, y)
post(.leftMouseDown, x, y)
for i in 1...10 { post(.leftMouseDragged, x + dx * Double(i) / 10, y + dy * Double(i) / 10) }
post(.leftMouseUp, x + dx, y + dy)
