import AppKit
import ScreenCaptureKit
import ZoeKit

/// A screenshot of the front window for one turn (#43): ScreenCaptureKit, written to a private temporary file the
/// core deletes when the turn ends. macOS asks for Screen Recording the first time.
@MainActor
enum Screenshot {
    static func frontWindow() async -> (path: String, app: String, detail: String) {
        guard let front = ScreenContext.frontmost() else { return ("", "", "no front app") }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let pid = front.processIdentifier
            let mine: [SCWindow] = content.windows.filter { w in
                let owner: pid_t? = w.owningApplication?.processID
                return owner == pid && w.windowLayer == 0 && w.frame.width > 50
            }
            guard let win = mine.first else { return ("", front.localizedName ?? "", "no window of the front app on screen") }
            let filter = SCContentFilter(desktopIndependentWindow: win)
            let cfg = SCStreamConfiguration()
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            cfg.width = Int(win.frame.width * scale)
            cfg.height = Int(win.frame.height * scale)
            cfg.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zoe-shots", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let url = dir.appendingPathComponent("shot-\(UUID().uuidString.prefix(8)).png")
            guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                return ("", front.localizedName ?? "", "couldn't encode the image")
            }
            try png.write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return (url.path, front.localizedName ?? "", "")
        } catch {
            return ("", front.localizedName ?? "", "Screen Recording permission is needed (\(error.localizedDescription))")
        }
    }
}
