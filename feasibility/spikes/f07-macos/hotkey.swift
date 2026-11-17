// F07: global push-to-talk via Carbon RegisterEventHotKey (no event tap). Reports press AND release of
// ⌃⌥Space for N seconds. Whether this needs Accessibility is the question; AXIsProcessTrusted is printed.
import AppKit
import Carbon.HIToolbox
import ApplicationServices
setvbuf(stdout, nil, _IOLBF, 0)
let secs = Double(CommandLine.arguments.dropFirst().first ?? "15") ?? 15
print("AXIsProcessTrusted=\(AXIsProcessTrusted())")
var spec = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
var down = 0.0
let st = InstallEventHandler(GetApplicationEventTarget(), { _, ev, _ in
    let kind = GetEventKind(ev); let t = Date().timeIntervalSince1970
    if kind == UInt32(kEventHotKeyPressed) { down = t; print(String(format: "%.3f PRESSED", t)) }
    else { print(String(format: "%.3f RELEASED (held %.2f s)", t, t - down)) }
    return noErr
}, 2, &spec, nil, nil)
var ref: EventHotKeyRef?
let r = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), EventHotKeyID(signature: OSType(0x46303748), id: 1),
                            GetApplicationEventTarget(), 0, &ref)
print("InstallEventHandler=\(st) RegisterEventHotKey=\(r)  -> hold ⌃⌥Space a few times within \(Int(secs)) s")
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
DispatchQueue.main.asyncAfter(deadline: .now() + secs) { print("done"); exit(0) }
app.run()
