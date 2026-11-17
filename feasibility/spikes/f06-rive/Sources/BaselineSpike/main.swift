// F06 baseline: same transparent panel, no Rive. A CoreAnimation circle that
// pulses (CABasicAnimation, rendered by the render server) or, with --timer N,
// is redrawn from a CVDisplayLink-like Timer at N fps (closer to Rive's model
// of app-side per-frame work).
//
// Usage: BaselineSpike [--timer N] [--paused] [--duration S]
import AppKit
import QuartzCore

setvbuf(stdout, nil, _IOLBF, 0)
func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}

final class DragView: NSView { override var mouseDownCanMoveWindow: Bool { true } }

final class Baseline: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    var shape = CAShapeLayer()
    var timer: Timer?
    var phase = 0.0

    func applicationDidFinishLaunching(_ n: Notification) {
        let size = NSSize(width: 240, height: 240)
        panel = NSPanel(contentRect: NSRect(origin: NSPoint(x: 500, y: 300), size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false

        let host = DragView(frame: NSRect(origin: .zero, size: size))
        host.wantsLayer = true
        shape.frame = host.bounds
        shape.path = CGPath(ellipseIn: host.bounds.insetBy(dx: 40, dy: 40), transform: nil)
        shape.fillColor = NSColor.systemOrange.cgColor
        host.layer!.addSublayer(shape)
        panel.contentView = host
        panel.orderFrontRegardless()

        if let t = arg("--timer"), let fps = Double(t) {
            timer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.phase += 1 / fps
                let s = 0.85 + 0.15 * sin(self.phase * 4)
                CATransaction.begin(); CATransaction.setDisableActions(true)
                self.shape.setAffineTransform(CGAffineTransform(translationX: 120 * (1 - s), y: 120 * (1 - s)).scaledBy(x: s, y: s))
                CATransaction.commit()
            }
        } else if !CommandLine.arguments.contains("--paused") {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1; a.toValue = 0.3; a.duration = 0.8
            a.autoreverses = true; a.repeatCount = .infinity
            shape.add(a, forKey: "pulse")
        }
        print("READY pid=\(getpid()) windowNumber=\(panel.windowNumber)")
        let dur = Double(arg("--duration") ?? "30") ?? 30
        DispatchQueue.main.asyncAfter(deadline: .now() + dur) { self.panel.close(); NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let d = Baseline()
app.delegate = d
app.run()
