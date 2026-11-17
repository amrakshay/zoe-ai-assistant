// F07 step 3: right-Option hold-to-talk detection. Tries NSEvent global monitor (flagsChanged) and CGEventTap
// (listen-only and default). Reports preflight permission state without prompting. With --synth it posts a
// synthetic right-Option down/up (keycode 61) to see whether either path receives it (posting needs Accessibility).
// With --wait N it just listens N seconds for a real key press.
import AppKit
import CoreGraphics
import ApplicationServices

let rightOptMask: UInt64 = 0x40          // NX_DEVICERALTKEYMASK (device-dependent bit in CGEventFlags)
let kRightOption: Int64 = 61
func ts() -> String { String(format: "%.3f", Date().timeIntervalSince1970) }

print("AXIsProcessTrusted=\(AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary))")
print("CGPreflightListenEventAccess (Input Monitoring)=\(CGPreflightListenEventAccess())")
print("CGPreflightPostEventAccess (Accessibility, posting)=\(CGPreflightPostEventAccess())")

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)

var nsCount = 0
let mon = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { e in
    nsCount += 1
    let right = (UInt64(e.modifierFlags.rawValue) & rightOptMask) != 0
    print("[\(ts())] NSEvent global flagsChanged keyCode=\(e.keyCode) rightOptDown=\(right)"); fflush(stdout)
}
print("NSEvent global monitor object created=\(mon != nil)")

var tapCounts = [String: Int]()
func makeTap(_ name: String, _ opt: CGEventTapOptions) -> CFMachPort? {
    let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
    let ref = Unmanaged.passRetained(name as NSString).toOpaque()
    let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: opt, eventsOfInterest: mask, callback: { _, type, ev, info in
        let n = Unmanaged<NSString>.fromOpaque(info!).takeUnretainedValue() as String
        if type == .flagsChanged {
            let kc = ev.getIntegerValueField(.keyboardEventKeycode)
            let right = (ev.flags.rawValue & rightOptMask) != 0
            print("[\(ts())] CGEventTap(\(n)) flagsChanged keycode=\(kc) rightOptDown=\(right)"); fflush(stdout)
        } else { print("[\(ts())] CGEventTap(\(n)) event type=\(type.rawValue) (tap disabled?)") }
        return Unmanaged.passUnretained(ev)
    }, userInfo: ref)
    print("CGEventTap(\(name)) created=\(tap != nil)")
    if let tap = tap {
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    return tap
}
let t1 = makeTap("listenOnly", .listenOnly)
let t2 = makeTap("default", .defaultTap)

// Permission-free fallback candidates: polling global modifier/key state
func pollState() -> String {
    let f = CGEventSource.flagsState(.combinedSessionState).rawValue
    let k = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kRightOption))
    return "flagsState=0x\(String(f, radix: 16)) rightOptBit=\((f & rightOptMask) != 0) keyState(61)=\(k)"
}

let args = CommandLine.arguments
if args.contains("--synth") {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kRightOption), keyDown: true)!
        down.type = .flagsChanged; down.flags = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | rightOptMask)
        print("[\(ts())] posting synthetic right-Option DOWN"); down.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { print("  during hold: \(pollState())") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kRightOption), keyDown: false)!
            up.type = .flagsChanged; up.flags = CGEventFlags(rawValue: 0x100)
            print("[\(ts())] posting synthetic right-Option UP"); up.post(tap: .cghidEventTap)
        }
    }
}
let wait = (args.firstIndex(of: "--wait").flatMap { Double(args[$0+1]) }) ?? 2.0
print("idle poll: \(pollState())")
RunLoop.main.run(until: Date().addingTimeInterval(wait))
print("done: NSEvent monitor events=\(nsCount)")
