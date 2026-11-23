import AppKit
import ApplicationServices

/// What's on screen (#42, PLAN.md §5.2): the frontmost app, its window title, the browser URL and the selected
/// text. Read through Accessibility (Zoe needs it anyway for the push-to-talk key).
///
/// - Chromium and Electron apps (Chrome, Slack, VS Code…) build their accessibility tree only when asked:
///   setting `AXManualAccessibility` on the app turns it on.
/// - If Accessibility gives no selection, `copySelection()` sends ⌘C and puts my clipboard back right after.
/// - All of it is **untrusted** content: the core taints the session when it arrives.
public struct ScreenSnapshot: Sendable, Equatable {
    public var app: String = ""
    public var bundleID: String = ""
    public var window: String = ""
    public var url: String = ""
    public var selection: String = ""
    public var selectionVia: String = ""      // "accessibility" | "copy" | ""

    public static let maxSelection = 8000

    public var dictionary: [String: Any] {
        ["app": app, "bundle_id": bundleID, "window": window, "url": url,
         "selection": selection, "selection_via": selectionVia]
    }
}

public enum ScreenContext {
    static let browsers: Set<String> = ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac",
                                        "company.thebrowser.Browser", "com.brave.Browser", "org.mozilla.firefox"]

    /// The frontmost app (not Zoe itself).
    public static func frontmost() -> NSRunningApplication? {
        let me = ProcessInfo.processInfo.processIdentifier
        let app = NSWorkspace.shared.frontmostApplication
        return app?.processIdentifier == me ? nil : app
    }

    public static func snapshot(copyIfNeeded: Bool = false) -> ScreenSnapshot {
        var s = ScreenSnapshot()
        guard let app = frontmost() else { return s }
        s.app = app.localizedName ?? ""
        s.bundleID = app.bundleIdentifier ?? ""
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.5)
        // Chromium / Electron: ask for the accessibility tree (harmless elsewhere).
        AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if let win: AXUIElement = attr(ax, kAXFocusedWindowAttribute) {
            s.window = (attr(win, kAXTitleAttribute) as String?) ?? ""
            if browsers.contains(s.bundleID) { s.url = findURL(win, depth: 0) ?? "" }
        }
        if let focused: AXUIElement = attr(ax, kAXFocusedUIElementAttribute),
           let sel: String = attr(focused, kAXSelectedTextAttribute), !sel.isEmpty {
            s.selection = String(sel.prefix(ScreenSnapshot.maxSelection))
            s.selectionVia = "accessibility"
        }
        if s.selection.isEmpty && copyIfNeeded, let copied = copySelection() {
            s.selection = String(copied.prefix(ScreenSnapshot.maxSelection))
            s.selectionVia = "copy"
        }
        return s
    }

    /// ⌘C in the frontmost app, read the copied text, then put the previous clipboard back exactly.
    public static func copySelection(wait: TimeInterval = 0.25) -> String? {
        let pb = NSPasteboard.general
        let saved = (pb.pasteboardItems ?? []).map { item -> [(NSPasteboard.PasteboardType, Data)] in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        }
        let before = pb.changeCount
        postKey(keyCode: 8, flags: .maskCommand)          // C
        let end = Date().addingTimeInterval(wait)
        while pb.changeCount == before && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        guard pb.changeCount != before else { return nil }
        let text = pb.string(forType: .string)
        pb.clearContents()
        let items = saved.map { pairs -> NSPasteboardItem in
            let it = NSPasteboardItem()
            for (t, d) in pairs { it.setData(d, forType: t) }
            return it
        }
        if !items.isEmpty { pb.writeObjects(items) }
        return text
    }

    public static func postKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    static func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success, let v else { return nil }
        if T.self == AXUIElement.self, CFGetTypeID(v) == AXUIElementGetTypeID() { return (v as! T) }
        return v as? T
    }

    /// The page URL: Safari and Chromium expose `AXURL` on the web area.
    static func findURL(_ el: AXUIElement, depth: Int) -> String? {
        if let u: URL = attr(el, kAXURLAttribute), u.scheme?.hasPrefix("http") == true { return u.absoluteString }
        if let u: String = attr(el, kAXURLAttribute), u.hasPrefix("http") { return u }
        guard depth < 8, let kids: [AXUIElement] = attr(el, kAXChildrenAttribute) else { return nil }
        for k in kids.prefix(40) { if let u = findURL(k, depth: depth + 1) { return u } }
        return nil
    }
}
