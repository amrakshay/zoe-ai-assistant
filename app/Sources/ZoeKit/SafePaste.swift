import AppKit
import ApplicationServices

/// Safe paste of a draft into the app I was using (#46, PLAN.md §5.8). It never presses Send or Enter.
public enum SafePaste {
    public static let terminals: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
                                                "com.mitchellh.ghostty", "net.kovidgoyal.kitty", "io.alacritty",
                                                "co.zeit.hyper", "com.github.wez.wezterm"]

    /// Trailing newlines and spaces are removed: in a terminal a final newline would run the command.
    public static func clean(_ text: String) -> String {
        var t = text
        while let last = t.last, last.isNewline || last == " " || last == "\t" { t.removeLast() }
        return t
    }

    public enum Verdict: Equatable { case paste(String), refuseMultiline }

    /// What may be pasted into an app: in a terminal, never more than one line (each line would run).
    public static func verdict(text: String, bundleID: String) -> Verdict {
        let t = clean(text)
        if terminals.contains(bundleID) && t.contains(where: \.isNewline) { return .refuseMultiline }
        return .paste(t)
    }

    /// Where a draft goes: the app and the focused field when I asked.
    public struct Target: @unchecked Sendable {
        public let pid: pid_t
        public let bundleID: String
        public let app: String
        let field: AXUIElement?

        public static func current() -> Target? {
            guard let app = ScreenContext.frontmost() else { return nil }
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            var v: CFTypeRef?
            let field = AXUIElementCopyAttributeValue(ax, kAXFocusedUIElementAttribute as CFString, &v) == .success && v != nil
                ? (v as! AXUIElement) : nil
            return Target(pid: app.processIdentifier, bundleID: app.bundleIdentifier ?? "", app: app.localizedName ?? "", field: field)
        }

        /// Still the same app and, if known, the same field in front?
        public func stillFrontmost() -> Bool {
            guard let now = Target.current(), now.pid == pid else { return false }
            guard let a = field, let b = now.field else { return true }
            return CFEqual(a, b)
        }
    }

    /// Puts `text` on the clipboard, sends ⌘V to the frontmost app, then restores the previous clipboard.
    @MainActor
    public static func paste(_ text: String, restoreAfter: Double = 0.4) {
        let pb = NSPasteboard.general
        let saved = (pb.pasteboardItems ?? []).map { item -> [(NSPasteboard.PasteboardType, Data)] in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        }
        pb.clearContents()
        pb.setString(text, forType: .string)
        ScreenContext.postKey(keyCode: 9, flags: .maskCommand)          // V — and nothing else: no Return
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreAfter) {
            pb.clearContents()
            let items = saved.map { pairs -> NSPasteboardItem in
                let it = NSPasteboardItem()
                for (t, d) in pairs { it.setData(d, forType: t) }
                return it
            }
            if !items.isEmpty { pb.writeObjects(items) }
        }
    }
}
