// F07 step 4: safe paste. Snapshot every pasteboard item/type, set test text (trailing newlines stripped),
// re-check the frontmost app is the expected one, send Cmd-V via CGEvent, then restore the snapshot and verify.
// Usage: paste <expected-bundle-id> <text>     (refuses to paste if frontmost != expected)
import AppKit
import ApplicationServices

func ts() -> String { String(format: "%.3f", Date().timeIntervalSince1970) }
func ms(_ t0: UInt64) -> String { String(format: "%.1f ms", Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6) }

/// Plan §5.8: strip trailing newlines (and CRs) so a terminal never runs the text. Inner newlines are kept.
func stripTrailingNewlines(_ s: String) -> String {
    var s = s
    while let last = s.unicodeScalars.last, last == "\n" || last == "\r" || last == "\u{2028}" || last == "\u{2029}" { s.unicodeScalars.removeLast() }
    return s
}

typealias Snapshot = [[(NSPasteboard.PasteboardType, Data)]]
func snapshot(_ pb: NSPasteboard) -> Snapshot {
    (pb.pasteboardItems ?? []).map { item in item.types.compactMap { t in item.data(forType: t).map { (t, $0) } } }
}
func restore(_ pb: NSPasteboard, _ snap: Snapshot) {
    pb.clearContents()
    let items: [NSPasteboardItem] = snap.map { pairs in let it = NSPasteboardItem(); for (t, d) in pairs { it.setData(d, forType: t) }; return it }
    if !items.isEmpty { pb.writeObjects(items) }
}
func same(_ a: Snapshot, _ b: Snapshot) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { x, y in x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 } }
}

let args = CommandLine.arguments
if args.count >= 2 && args[1] == "--selftest" {
    let cases: [(String, String)] = [("ls -la\n", "ls -la"), ("a\nb\n\n", "a\nb"), ("x\r\n", "x"), ("no newline", "no newline"), ("\n", ""), ("keep\n inner", "keep\n inner")]
    for (i, o) in cases { let r = stripTrailingNewlines(i); print("strip \(i.debugDescription) -> \(r.debugDescription) \(r == o ? "OK" : "FAIL")") }
    exit(0)
}
guard args.count >= 3 else { print("usage: paste <bundle-id> <text> | --selftest"); exit(2) }
let expected = args[1]; let text = stripTrailingNewlines(args[2])
print("AXIsProcessTrusted=\(AXIsProcessTrusted()) CGPreflightPostEventAccess=\(CGPreflightPostEventAccess())")

let pb = NSPasteboard.general
var t = DispatchTime.now().uptimeNanoseconds
let before = snapshot(pb)
let beforeChange = pb.changeCount
print("snapshot: items=\(before.count) types=\(before.map { $0.map { $0.0.rawValue } }) bytes=\(before.flatMap { $0 }.reduce(0) { $0 + $1.1.count }) (\(ms(t)))")

// Re-check frontmost immediately before paste (§5.8 step 2)
let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
guard front == expected else { print("ABORT: frontmost is \(front), expected \(expected); nothing pasted, clipboard untouched"); exit(3) }
print("frontmost check OK: \(front)")

t = DispatchTime.now().uptimeNanoseconds
pb.clearContents(); pb.setString(text, forType: .string)
let src = CGEventSource(stateID: .combinedSessionState)
let vDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)!; vDown.flags = .maskCommand
let vUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)!; vUp.flags = .maskCommand
vDown.post(tap: .cghidEventTap); vUp.post(tap: .cghidEventTap)
print("[\(ts())] posted Cmd-V (\(ms(t)))")
// Give the target time to read the pasteboard before restoring. Too short and it pastes the old clipboard.
Thread.sleep(forTimeInterval: Double(ProcessInfo.processInfo.environment["F07_RESTORE_DELAY"] ?? "0.25") ?? 0.25)
t = DispatchTime.now().uptimeNanoseconds
restore(pb, before)
let after = snapshot(pb)
if !same(before, after) {
    for (i, (x, y)) in zip(before, after).enumerated() {
        let dx = Dictionary(x, uniquingKeysWith: { a, _ in a }), dy = Dictionary(y, uniquingKeysWith: { a, _ in a })
        for k in Set(dx.keys).union(dy.keys) where dx[k] != dy[k] { print("  diff item\(i) \(k.rawValue): before=\(dx[k]?.count ?? -1)B after=\(dy[k]?.count ?? -1)B") }
    }
}
// Compare only the types that were captured before (derived types like utf16-external may appear/disappear)
let coreSame = before.count == after.count && zip(before, after).allSatisfy { x, y in let dy = Dictionary(y, uniquingKeysWith: { a, _ in a }); return x.allSatisfy { dy[$0.0] == $0.1 } }
print("restore: allOriginalTypesRestored=\(coreSame) exactSnapshotMatch=\(same(before, after)) items=\(after.count) changeCount \(beforeChange)->\(pb.changeCount) (\(ms(t)))")
