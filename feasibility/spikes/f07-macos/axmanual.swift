// F07: Chromium/Electron apps expose their AX tree only after AXManualAccessibility (or AXEnhancedUserInterface)
// is set on the app element. Sets it on the frontmost app, then reads focused element + selected text.
import AppKit
import ApplicationServices
let app = NSWorkspace.shared.frontmostApplication!
let ax = AXUIElementCreateApplication(app.processIdentifier)
let r = AXUIElementSetAttributeValue(ax, (ProcessInfo.processInfo.environment["AXATTR"] ?? "AXManualAccessibility") as CFString, kCFBooleanTrue)
print("frontmost=\(app.bundleIdentifier ?? "?") set AXManualAccessibility err=\(r.rawValue)")
for delay in [0.0, 0.3, 1.0] {
    Thread.sleep(forTimeInterval: delay)
    var foc: CFTypeRef?
    let e = AXUIElementCopyAttributeValue(ax, kAXFocusedUIElementAttribute as CFString, &foc)
    var sel = "-"; var e3 = AXError.failure; var role = "-"
    if e == .success, let f = foc {
        var v: CFTypeRef?; e3 = AXUIElementCopyAttributeValue(f as! AXUIElement, kAXSelectedTextAttribute as CFString, &v)
        if e3 == .success { sel = (v as? String) ?? "-" }
        var rv: CFTypeRef?; if AXUIElementCopyAttributeValue(f as! AXUIElement, kAXRoleAttribute as CFString, &rv) == .success { role = (rv as? String) ?? "-" }
    }
    print("after \(delay)s: focusedErr=\(e.rawValue) role=\(role) selErr=\(e3.rawValue) selected=\"\(sel.prefix(60))\"")
}
