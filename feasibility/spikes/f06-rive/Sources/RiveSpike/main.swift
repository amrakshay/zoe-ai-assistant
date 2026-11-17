// F06 spike: Rive character in a transparent, borderless, non-activating,
// always-on-top, all-Spaces, draggable NSPanel. Uses the legacy RiveViewModel
// API (deprecated in 6.30 in favour of the "concurrency runtime", still works).
//
// Usage:
//   RiveSpike --list <file.riv>
//   RiveSpike --riv <file.riv> [--sm <name>] [--fps N] [--paused] [--duration S]
//             [--artboard name] [--set name=value ...] [--set-at S]
import AppKit
import RiveRuntime

setvbuf(stdout, nil, _IOLBF, 0)

func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}
func args(_ name: String) -> [String] {
    let a = CommandLine.arguments
    return a.indices.compactMap { a[$0] == name && $0 + 1 < a.count ? a[$0 + 1] : nil }
}
let flag = { (n: String) in CommandLine.arguments.contains(n) }

// ---------- --list ----------
if let path = arg("--list") {
    let data = try! Data(contentsOf: URL(fileURLWithPath: path))
    guard let file = try? RiveFile(data: data, loadCdn: false) else { print("load failed"); exit(1) }
    for abName in file.artboardNames() {
        guard let ab = try? file.artboard(fromName: abName) else { continue }
        print("artboard: \(abName)  \(Int(ab.width()))x\(Int(ab.height()))")
        for smName in ab.stateMachineNames() {
            guard let sm = try? ab.stateMachine(fromName: smName) else { continue }
            var ins: [String] = []
            for i in 0..<sm.inputCount() {
                guard let inp = try? sm.input(from: i) else { continue }
                let kind = inp.isBoolean() ? "bool" : inp.isNumber() ? "number" : inp.isTrigger() ? "trigger" : "?"
                ins.append("\(inp.name()):\(kind)")
            }
            print("  state machine: \(smName)  inputs: [\(ins.joined(separator: ", "))]")
        }
    }
    exit(0)
}

// ---------- panel ----------
final class DragView: NSView {
    // Background drag: the panel has isMovableByWindowBackground = true, and this
    // view (and RiveView via hitTest override below) report mouseDownCanMoveWindow.
    override var mouseDownCanMoveWindow: Bool { true }
}

// Transparent overlay above the RiveView. RiveView overrides mouseDown (it feeds
// pointer events to the state machine), so it swallows background drags; this
// overlay hands the drag to the window server instead.
final class DragOverlay: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override var mouseDownCanMoveWindow: Bool { true }
}

// Counts advances (one per rendered frame) to verify the fps cap took effect.
final class CountingVM: RiveViewModel {
    var frames = 0
    override func player(didAdvanceby seconds: Double, riveModel: RiveModel?) {
        frames += 1
        super.player(didAdvanceby: seconds, riveModel: riveModel)
    }
}

final class Spike: NSObject, NSApplicationDelegate, RiveStateMachineDelegate {
    var panel: NSPanel!
    var vm: CountingVM!
    let t0 = Date()

    func applicationDidFinishLaunching(_ n: Notification) {
        let path = arg("--riv")!
        let url = URL(fileURLWithPath: path)
        let data = try! Data(contentsOf: url)
        let file = try! RiveFile(data: data, loadCdn: false)
        let model = RiveModel(riveFile: file)
        let smName = arg("--sm")
        vm = CountingVM(model, stateMachineName: smName, fit: .contain, autoPlay: true, artboardName: arg("--artboard"))

        let size = NSSize(width: 240, height: 240)
        panel = NSPanel(contentRect: NSRect(origin: NSPoint(x: 200, y: 300), size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        let host = DragView(frame: NSRect(origin: .zero, size: size))
        let rv = vm.createRiveView()
        rv.frame = host.bounds
        rv.autoresizingMask = [.width, .height]
        rv.stateMachineDelegate = self
        host.addSubview(rv)
        if flag("--drag-overlay") {
            let ov = DragOverlay(frame: host.bounds)
            ov.autoresizingMask = [.width, .height]
            host.addSubview(ov)
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { _ in
            self.log("MOVED frame=\(self.panel.frame)")
        }
        panel.contentView = host
        panel.orderFrontRegardless()

        if let f = arg("--fps"), let n = Int(f) { vm.setPreferredFramesPerSecond(preferredFramesPerSecond: n) }
        if flag("--paused") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.vm.pause(); self.log("paused") }
        }
        print("READY pid=\(getpid()) windowNumber=\(panel.windowNumber) frame=\(panel.frame) " +
              "level=\(panel.level.rawValue) opaque=\(panel.isOpaque) " +
              "behavior=\(panel.collectionBehavior.rawValue) movableByBg=\(panel.isMovableByWindowBackground) " +
              "metalLayerOpaque=\(rv.layer?.isOpaque.description ?? "nil") sm=\(vm.riveModel?.stateMachine?.name() ?? "nil")")

        let hit = host.hitTest(NSPoint(x: size.width / 2, y: size.height / 2))
        print("HITTEST centre -> \(hit.map { String(describing: type(of: $0)) } ?? "nil") " +
              "mouseDownCanMoveWindow=\(hit?.mouseDownCanMoveWindow.description ?? "nil")")
        let sets = args("--set")
        if !sets.isEmpty {
            let at = Double(arg("--set-at") ?? "3") ?? 3
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { self.apply(sets) }
        }
        // --cycle name:max:ms  -> step a number input 0...max every ms (simulates talking)
        if let c = arg("--cycle") {
            let p = c.split(separator: ":").map(String.init)
            let (name, maxV, ms) = (p[0], Double(p[1])!, Double(p[2])!)
            var v = 0.0
            Timer.scheduledTimer(withTimeInterval: ms / 1000, repeats: true) { _ in
                v = v >= maxV ? 0 : v + 1
                self.vm.setInput(name, value: v)
            }
        }
        // Report measured frame rate every 5 s.
        var last = 0
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            self.log("frames/s over last 5 s: \(Double(self.vm.frames - last) / 5)")
            last = self.vm.frames
        }
        let dur = Double(arg("--duration") ?? "30") ?? 30
        DispatchQueue.main.asyncAfter(deadline: .now() + dur) {
            self.log("done; closing panel")
            self.panel.close()
            NSApp.terminate(nil)
        }
    }

    func apply(_ sets: [String]) {
        guard let sm = vm.riveModel?.stateMachine else { log("no state machine"); return }
        for s in sets {
            let kv = s.split(separator: "=", maxSplits: 1).map(String.init)
            let (name, val) = (kv[0], kv[1])
            if val == "fire" {
                vm.triggerInput(name); log("SET trigger \(name) fired")
            } else if val == "true" || val == "false" {
                let before = sm.getBool(name).value()
                vm.setInput(name, value: val == "true")
                log("SET bool \(name): \(before) -> \(sm.getBool(name).value())")
            } else if let d = Double(val) {
                let before = sm.getNumber(name).value()
                vm.setInput(name, value: d)
                log("SET number \(name): \(before) -> \(sm.getNumber(name).value())")
            }
        }
    }

    func log(_ s: String) { print(String(format: "[%6.2fs] ", Date().timeIntervalSince(t0)) + s) }

    // Callbacks proving the state machine reacted.
    func stateMachine(_ stateMachine: RiveStateMachineInstance, didChangeState stateName: String) {
        log("STATE \(stateMachine.name()) -> \(stateName)")
    }
    func stateMachine(_ stateMachine: RiveStateMachineInstance, receivedInput input: StateMachineInput) {
        log("INPUT callback \(input)")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = Spike()
app.delegate = delegate
app.run()
