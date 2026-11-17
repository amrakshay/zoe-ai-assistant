// F07 helper: show clipboard types; --seed puts a 2-item, multi-type test clipboard (only used when the clipboard is empty)
import AppKit
let pb = NSPasteboard.general
if CommandLine.arguments.contains("--seed") {
    let a = NSPasteboardItem(); a.setString("F07 original clipboard", forType: .string)
    a.setData("{\\rtf1 F07 {\\b original}}".data(using: .utf8)!, forType: .rtf)
    a.setData(Data([0, 1, 2, 255]), forType: NSPasteboard.PasteboardType("dev.f07.custom"))
    let b = NSPasteboardItem(); b.setString("https://example.com/f07", forType: .URL); b.setString("second item", forType: .string)
    pb.clearContents(); pb.writeObjects([a, b])
}
if CommandLine.arguments.contains("--clear") { pb.clearContents() }
print("changeCount=\(pb.changeCount) items=\(pb.pasteboardItems?.count ?? -1) types=\(pb.pasteboardItems?.map { $0.types.map { $0.rawValue } } ?? []) string=\(pb.string(forType: .string)?.debugDescription ?? "nil")")
