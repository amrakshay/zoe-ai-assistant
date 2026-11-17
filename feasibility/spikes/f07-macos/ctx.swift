// F07 step 2: frontmost context. NSWorkspace (no permission), AX focused window title + selected text
// (Accessibility), browser URL via AppleScript (Automation). Never prompts: AXIsProcessTrustedWithOptions(prompt=false).
import AppKit
import ApplicationServices

func ms(_ t0: UInt64) -> String { String(format: "%.2f ms", Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6) }
func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

var t = now()
let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary)
print("AXIsProcessTrusted=\(trusted) (\(ms(t)))")

t = now()
let app = NSWorkspace.shared.frontmostApplication
print("frontmost: name=\(app?.localizedName ?? "nil") bundle=\(app?.bundleIdentifier ?? "nil") pid=\(app?.processIdentifier ?? -1) (\(ms(t)))")

if let pid = app?.processIdentifier {
    t = now()
    let ax = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(ax, 0.5)
    var win: CFTypeRef?
    let e1 = AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &win)
    var title = "-"
    if e1 == .success, let w = win {
        var v: CFTypeRef?
        if AXUIElementCopyAttributeValue(w as! AXUIElement, kAXTitleAttribute as CFString, &v) == .success { title = (v as? String) ?? "-" }
    }
    print("AX focused window: err=\(e1.rawValue) title=\(title.prefix(80)) (\(ms(t)))  [-25211=apiDisabled/not trusted]")
    t = now()
    let sys = AXUIElementCreateSystemWide()
    var foc: CFTypeRef?
    // The system-wide element often returns -25204 (cannotComplete); ask the frontmost app's element first.
    var e2 = AXUIElementCopyAttributeValue(ax, kAXFocusedUIElementAttribute as CFString, &foc)
    var via = "app"
    if e2 != .success { e2 = AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &foc); via = "system-wide" }
    var sel = "-"; var e3 = AXError.failure
    if e2 == .success, let f = foc {
        var v: CFTypeRef?
        e3 = AXUIElementCopyAttributeValue(f as! AXUIElement, kAXSelectedTextAttribute as CFString, &v)
        if e3 == .success { sel = (v as? String) ?? "-" }
    }
    print("AX selected text (via \(via)): focusedErr=\(e2.rawValue) selErr=\(e3.rawValue) len=\(sel == "-" ? 0 : sel.count) text=\"\(sel.prefix(60))\" (\(ms(t)))")
}

// Window titles without Accessibility: CGWindowList (kCGWindowName needs Screen Recording on 10.15+)
t = now()
let wl = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
let fw = wl.first { ($0[kCGWindowOwnerPID as String] as? Int32) == app?.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0 }
print("CGWindowList frontmost window name present=\(fw?[kCGWindowName as String] != nil) (\(ms(t))) [needs Screen Recording]")

// Browser URL via AppleScript, only for browsers already running (never launches one)
let browsers: [(String, String)] = [("com.apple.Safari", "tell application id \"com.apple.Safari\" to get URL of current tab of front window"),
                                    ("com.google.Chrome", "tell application id \"com.google.Chrome\" to get URL of active tab of front window"),
                                    ("com.brave.Browser", "tell application id \"com.brave.Browser\" to get URL of active tab of front window")]
let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
let doURL = CommandLine.arguments.contains("--url")
for (bid, src) in browsers {
    guard running.contains(bid) else { print("browser \(bid): not running, skipped"); continue }
    guard doURL else { print("browser \(bid): running; pass --url to query (may show Automation prompt)"); continue }
    t = now()
    var err: NSDictionary?
    let r = NSAppleScript(source: src)?.executeAndReturnError(&err)
    if let r = r { print("browser \(bid): URL host=\(URL(string: r.stringValue ?? "")?.host ?? "?") (\(ms(t)))") }
    else { print("browser \(bid): error \(err?["NSAppleScriptErrorNumber"] ?? "?") \(err?["NSAppleScriptErrorMessage"] ?? "") (\(ms(t))) [-1743=Automation not permitted]") }
}
