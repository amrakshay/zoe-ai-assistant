import AppKit
import QuartzCore

/// The floating character (#6): a borderless, transparent, non-activating panel on every Space and over
/// full-screen apps, holding a placeholder orb drawn with Core Animation (our own artwork, no licence
/// question). A Rive character can replace `OrbView` later behind the same `state` / `level` interface.
///
/// Cost: idle is a static frame (no timers, no animations, so ~0 % CPU); active states use Core Animation,
/// which the render server runs, plus level updates at ≤ 20 Hz.
@MainActor
final class CharacterWindow {
    enum State: Equatable { case idle, listening, thinking, talking, offline, inCall }

    let panel: NSPanel
    let orb: OrbView
    var onClick: (() -> Void)?
    /// Called after the panel moved (to re-place the bubble).
    var onMove: (() -> Void)?

    static let size = NSSize(width: 112, height: 112)
    private static let originKey = "characterOrigin"

    init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false            // OrbView moves it itself, so a drag isn't taken as a click
        orb = OrbView(frame: NSRect(origin: .zero, size: Self.size))
        panel.contentView = orb
        orb.onClick = { [weak self] in self?.onClick?() }
        orb.onDragged = { [weak self] in self?.savePosition(); self?.onMove?() }
        panel.setFrameOrigin(Self.savedOrigin() ?? Self.defaultOrigin())
    }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }
    var isVisible: Bool { panel.isVisible }

    var state: State = .idle { didSet { if state != oldValue { orb.apply(state) } } }
    /// How many things wait for me (approvals, questions, Terminal cards): the badge (#21).
    var waiting = 0 { didSet { if waiting != oldValue { orb.setWaiting(waiting) } } }
    func level(_ v: Float) { orb.level(v) }

    private func savePosition() {
        let o = panel.frame.origin
        UserDefaults.standard.set([o.x, o.y], forKey: Self.originKey)
    }

    private static func savedOrigin() -> NSPoint? {
        guard let a = UserDefaults.standard.array(forKey: originKey) as? [Double], a.count == 2 else { return nil }
        let p = NSPoint(x: a[0], y: a[1])
        // Only if it's still on a connected screen.
        return NSScreen.screens.contains { $0.visibleFrame.insetBy(dx: -20, dy: -20).contains(NSRect(origin: p, size: size)) } ? p : nil
    }

    private static func defaultOrigin() -> NSPoint {
        let f = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSPoint(x: f.maxX - size.width - 24, y: f.minY + 24)
    }
}

/// A soft orb with two eyes. Listening: a halo that follows my voice. Thinking: a spinning arc.
/// Talking: the orb swells with Zoe's voice. Idle: still. Offline / in a call: grey.
@MainActor
final class OrbView: NSView {
    var onClick: (() -> Void)?
    var onDragged: (() -> Void)?

    private let body = CAGradientLayer()
    private let halo = CAShapeLayer()
    private let arc = CAShapeLayer()
    private let eyes = CALayer()
    private let leftEye = CALayer(), rightEye = CALayer()
    private let badge = CALayer()
    private let badgeText = CATextLayer()
    private let hand = CATextLayer()
    private var state: CharacterWindow.State = .idle
    private var smoothed: Float = 0
    private var dragStart: NSPoint?
    private var dragged = false
    private var hovering = false { didSet { body.opacity = bodyOpacity } }

    private let d: CGFloat = 64     // orb diameter

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
        let r = CGRect(x: (frame.width - d) / 2, y: (frame.height - d) / 2, width: d, height: d)

        halo.frame = bounds
        halo.path = CGPath(ellipseIn: r.insetBy(dx: -6, dy: -6), transform: nil)
        halo.fillColor = .clear
        halo.lineWidth = 3
        halo.opacity = 0
        layer?.addSublayer(halo)

        body.frame = r
        body.type = .radial
        body.startPoint = CGPoint(x: 0.35, y: 0.7)
        body.endPoint = CGPoint(x: 1.1, y: -0.1)
        body.cornerRadius = d / 2
        body.masksToBounds = true
        body.shadowOpacity = 0
        layer?.addSublayer(body)

        arc.frame = bounds
        arc.path = CGPath(ellipseIn: r.insetBy(dx: -7, dy: -7), transform: nil)
        arc.fillColor = .clear
        arc.lineWidth = 3
        arc.lineCap = .round
        arc.strokeStart = 0
        arc.strokeEnd = 0.22
        arc.opacity = 0
        layer?.addSublayer(arc)

        eyes.frame = r
        for (e, x) in [(leftEye, d * 0.36), (rightEye, d * 0.64)] {
            e.bounds = CGRect(x: 0, y: 0, width: 7, height: 10)
            e.position = CGPoint(x: x, y: d * 0.56)
            e.cornerRadius = 3.5
            e.backgroundColor = CGColor(gray: 1, alpha: 0.95)
            eyes.addSublayer(e)
        }
        layer?.addSublayer(eyes)

        // Count badge (#21): amber, top right of the orb; a raised hand at top left while anything waits.
        let bd: CGFloat = 22
        badge.frame = CGRect(x: r.maxX - bd + 6, y: r.maxY - bd + 6, width: bd, height: bd)
        badge.cornerRadius = bd / 2
        badge.backgroundColor = CGColor(red: 1.0, green: 0.62, blue: 0.10, alpha: 1)
        badge.borderColor = CGColor(gray: 1, alpha: 0.95); badge.borderWidth = 2
        badgeText.frame = badge.bounds.offsetBy(dx: 0, dy: -3)
        badgeText.alignmentMode = .center
        badgeText.fontSize = 12; badgeText.font = NSFont.boldSystemFont(ofSize: 12)
        badgeText.foregroundColor = CGColor(gray: 1, alpha: 1)
        badgeText.contentsScale = 2
        badge.addSublayer(badgeText)
        hand.string = "✋"; hand.fontSize = 18; hand.contentsScale = 2
        hand.frame = CGRect(x: r.minX - 12, y: r.maxY - 14, width: 26, height: 26)
        for l in [badge, hand] as [CALayer] { l.opacity = 0; layer?.addSublayer(l) }

        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        apply(.idle)
    }

    required init?(coder: NSCoder) { fatalError() }

    // Only the orb itself takes clicks; the transparent corners pass through.
    override func hitTest(_ p: NSPoint) -> NSView? {
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        return hypot(p.x - c.x, p.y - c.y) <= d / 2 + 6 ? self : nil
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var bodyOpacity: Float {
        switch state {
        case .offline, .inCall: return 0.55
        case .idle: return hovering ? 1 : 0.9
        default: return 1
        }
    }

    private func colors(_ s: CharacterWindow.State) -> (CGColor, CGColor, CGColor) {
        func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: 1) }
        switch s {
        case .idle:      return (c(0.72, 0.62, 1.00), c(0.42, 0.30, 0.86), c(0.55, 0.45, 0.95))
        case .listening: return (c(0.55, 0.92, 0.95), c(0.18, 0.55, 0.78), c(0.35, 0.85, 0.95))
        case .thinking:  return (c(0.75, 0.70, 1.00), c(0.38, 0.30, 0.80), c(1.00, 0.78, 0.35))
        case .talking:   return (c(0.85, 0.66, 1.00), c(0.52, 0.28, 0.90), c(0.80, 0.60, 1.00))
        case .offline, .inCall: return (c(0.70, 0.70, 0.74), c(0.40, 0.40, 0.45), c(0.55, 0.55, 0.60))
        }
    }

    func apply(_ s: CharacterWindow.State) {
        state = s
        let (light, dark, accent) = colors(s)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        body.colors = [light, dark]
        body.opacity = bodyOpacity
        halo.strokeColor = accent
        arc.strokeColor = accent
        halo.opacity = s == .listening ? 0.8 : 0
        arc.opacity = s == .thinking ? 1 : 0
        body.setAffineTransform(.identity)
        halo.setAffineTransform(.identity)
        // Eyes: closed (a line) when offline or in a call.
        let closed = s == .offline || s == .inCall
        for e in [leftEye, rightEye] { e.bounds.size.height = closed ? 2.5 : 10 }
        CATransaction.commit()

        arc.removeAnimation(forKey: "spin")
        eyes.removeAnimation(forKey: "blink")
        if s == .thinking {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0; spin.toValue = -2 * Double.pi
            spin.duration = 1.1; spin.repeatCount = .infinity
            arc.add(spin, forKey: "spin")
        }
        if s == .listening || s == .talking || s == .thinking {   // blink now and then; none when idle (0 % CPU)
            let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
            blink.values = [1, 1, 0.1, 1]; blink.keyTimes = [0, 0.94, 0.97, 1]
            blink.duration = 4.2; blink.repeatCount = .infinity
            eyes.add(blink, forKey: "blink")
        }
        smoothed = 0
    }

    func setWaiting(_ n: Int) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        badgeText.string = n > 9 ? "9+" : "\(n)"
        badge.opacity = n > 0 ? 1 : 0
        hand.opacity = n > 0 ? 1 : 0
        CATransaction.commit()
    }

    /// Mic level while listening, Zoe's voice level while talking.
    func level(_ v: Float) {
        guard state == .listening || state == .talking else { return }
        let x = min(1, v * (state == .listening ? 14 : 6))        // speech RMS is ~0.01–0.1
        smoothed = max(x, smoothed * 0.6)
        let k = CGFloat(smoothed)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.09)
        if state == .listening { halo.setAffineTransform(CGAffineTransform(scaleX: 1 + 0.18 * k, y: 1 + 0.18 * k)) }
        else { body.setAffineTransform(CGAffineTransform(scaleX: 1 + 0.14 * k, y: 1 + 0.14 * k)) }
        CATransaction.commit()
    }

    // MARK: click and drag

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with e: NSEvent) { dragStart = NSEvent.mouseLocation; dragged = false }

    override func mouseDragged(with e: NSEvent) {
        guard let start = dragStart, let w = window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - start.x, dy = now.y - start.y
        if !dragged && hypot(dx, dy) < 4 { return }
        dragged = true
        w.setFrameOrigin(NSPoint(x: w.frame.origin.x + dx, y: w.frame.origin.y + dy))
        dragStart = now
    }

    override func mouseUp(with e: NSEvent) {
        if dragged { onDragged?() } else { onClick?() }
        dragStart = nil; dragged = false
    }
}
