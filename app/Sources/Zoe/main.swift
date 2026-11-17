// Zoe menu-bar app (phase 1 skeleton, #1): spawns and supervises the core, shows its state, and sends a
// typed test utterance. Audio (#3–#5) and the character (#6) come next.
//
// Flags:
//   --smoke "text"   start the core, send one utterance, print the reply and timings, quit (no UI)
import AppKit
import ZoeKit

setvbuf(stdout, nil, _IOLBF, 0)

/// Where the core project lives: `ZOE_CORE_DIR`, else `<repo>/core` next to this source file (dev builds).
func coreDirectory() -> URL {
    if let d = ProcessInfo.processInfo.environment["ZOE_CORE_DIR"] { return URL(fileURLWithPath: d) }
    return URL(fileURLWithPath: #filePath)            // <repo>/app/Sources/Zoe/main.swift
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("core")
}

// MARK: - smoke mode

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--smoke") {
    let text = i + 1 < args.count ? args[i + 1] : "hello"
    let link = CoreLink(command: .development(coreDir: coreDirectory()), callbackQueue: DispatchQueue(label: "smoke"))
    let done = DispatchSemaphore(value: 0)
    let t0 = Date()
    nonisolated(unsafe) var sentAt = Date()
    link.onLog = { FileHandle.standardError.write(Data($0.utf8)) }
    link.onState = { s in
        print("state: \(s)")
        if case .ready = s {
            print(String(format: "ready after %.0f ms", Date().timeIntervalSince(t0) * 1000))
            sentAt = Date()
            link.send(CoreMessage("utterance", ["id": "smoke-1", "text": text, "trigger": "text"]))
        }
    }
    link.onMessage = { m in
        if m.type == "say" {
            print("say: \(m.string("text") ?? "")")
            print(String(format: "reply after %.0f ms", Date().timeIntervalSince(sentAt) * 1000))
            done.signal()
        }
    }
    link.start()
    let ok = done.wait(timeout: .now() + 30) == .success
    link.stop()
    Thread.sleep(forTimeInterval: 0.3)
    exit(ok ? 0 : 1)
}

// MARK: - menu-bar app

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let stateItem = NSMenuItem(title: "Core: starting…", action: nil, keyEquivalent: "")
    private let replyItem = NSMenuItem(title: "No reply yet", action: nil, keyEquivalent: "")
    private var link: CoreLink!
    private var counter = 0

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Zoe ○"
        let menu = NSMenu()
        stateItem.isEnabled = false; replyItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(replyItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Send a Test Message…", action: #selector(sendTest), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "Restart Core", action: #selector(restartCore), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Zoe", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        startLink()
    }

    private func startLink() {
        link = CoreLink(command: .development(coreDir: coreDirectory()))
        link.onLog = { FileHandle.standardError.write(Data($0.utf8)) }
        link.onState = { [weak self] s in MainActor.assumeIsolated { self?.show(s) } }
        link.onMessage = { [weak self] m in MainActor.assumeIsolated { self?.handle(m) } }
        link.onPendingDenied = { ids in print("core restarted: denied \(ids.count) pending approval(s)") }
        link.start()
    }

    private func show(_ s: LinkState) {
        switch s {
        case .starting: stateItem.title = "Core: starting…"; statusItem.button?.title = "Zoe ○"
        case .ready(let pid): stateItem.title = "Core: ready (pid \(pid))"; statusItem.button?.title = "Zoe ●"
        case .offline(let why): stateItem.title = "Core: offline — \(why)"; statusItem.button?.title = "Zoe ⊘"
        case .stopped: stateItem.title = "Core: stopped"; statusItem.button?.title = "Zoe ○"
        }
        print("core state: \(s)")
    }

    private func handle(_ m: CoreMessage) {
        switch m.type {
        case "say": replyItem.title = m.string("text") ?? ""
        case "state": print("assistant state: \(m.string("value") ?? "?")")
        case "error": print("core error: \(m.string("message") ?? "?")")
        default: break
        }
    }

    @objc private func sendTest() {
        let alert = NSAlert()
        alert.messageText = "Send a test message to the core"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = "Hello Zoe"
        alert.accessoryView = field
        alert.addButton(withTitle: "Send"); alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        counter += 1
        link.send(CoreMessage("utterance", ["id": "u\(counter)", "text": field.stringValue, "trigger": "text"]))
    }

    @objc private func restartCore() { link.stop(); startLink() }
    @objc private func quit() { link.stop(); NSApp.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
