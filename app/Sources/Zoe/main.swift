// Zoe menu-bar app (phase 1 skeleton, #1): spawns and supervises the core, shows its state, and sends a
// typed test utterance. Audio (#3–#5) and the character (#6) come next.
//
// Flags:
//   --smoke "text"   start the core, send the utterance(s) (separate several with " || "), print the
//                    replies and timings, quit (no UI)
//   --listen-test N  start a hands-free conversation for N seconds, print VAD turns and timings, quit
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
    let texts = (i + 1 < args.count ? args[i + 1] : "hello").components(separatedBy: " || ")
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
            print("> \(texts[0])")
            link.send(CoreMessage("utterance", ["id": "smoke-1", "text": texts[0], "trigger": "text"]))
        }
    }
    nonisolated(unsafe) var firstSay: Double?
    nonisolated(unsafe) var turn = 0
    link.onMessage = { m in
        switch m.type {
        case "say":
            let t = Date().timeIntervalSince(sentAt) * 1000
            if let text = m.string("text"), !text.isEmpty {
                if firstSay == nil { firstSay = t; print(String(format: "first sentence after %.0f ms", t)) }
                print("say: \(text)")
            }
            if (m["final"] as? Bool) == true {
                print(String(format: "reply complete after %.0f ms", t))
                turn += 1
                if turn < texts.count {
                    firstSay = nil; sentAt = Date()
                    print("> \(texts[turn])")
                    link.send(CoreMessage("utterance", ["id": "smoke-\(turn + 1)", "text": texts[turn], "trigger": "text"]))
                } else { done.signal() }
            }
        case "state": print("assistant: \(m.string("value") ?? "?")")
        case "error": print("core error: \(m.string("message") ?? "?")")
        default: break
        }
    }
    link.start()
    let ok = done.wait(timeout: .now() + .seconds(120 * texts.count)) == .success
    link.stop()
    Thread.sleep(forTimeInterval: 0.3)
    exit(ok ? 0 : 1)
}

// MARK: - speech-to-text bench

if let i = args.firstIndex(of: "--stt-bench") {
    // Loads Whisper (timed), then transcribes a 16 kHz mono WAV if given. Prints time, CPU and peak RSS.
    let wav = i + 1 < args.count ? args[i + 1] : nil
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        let stt = WhisperSTT()
        do {
            try await stt.load()
            print(String(format: "load: %.0f ms", await stt.lastLoadMillis))
            if let wav {
                let samples = try WAV.read16kMono(URL(fileURLWithPath: wav))
                for n in 1...2 {
                    let r = try await stt.transcribe(samples)
                    print(String(format: "transcribe #%d (%.2f s audio): %.0f ms: %@", n, Double(samples.count) / 16000, r.millis, r.text))
                }
            }
        } catch { print("error: \(error)") }
        var ru = rusage(); getrusage(RUSAGE_SELF, &ru)
        print(String(format: "cpu %.2f s, max RSS %.0f MB", Double(ru.ru_utime.tv_sec + ru.ru_stime.tv_sec) + Double(ru.ru_utime.tv_usec + ru.ru_stime.tv_usec) / 1e6, Double(ru.ru_maxrss) / 1048576))
        done.signal()
    }
    done.wait()
    exit(0)
}

// MARK: - listen test

if let i = args.firstIndex(of: "--listen-test") {
    let secs = i + 1 < args.count ? Double(args[i + 1]) ?? 12 : 12
    MainActor.assumeIsolated {
        let v = VoiceController()
        v.onStatus = { print("voice: \($0)") }
        v.onUIState = { print("state: \($0)") }
        v.onTurn = { s in print(String(format: "turn: %.2f s of audio", Double(s.count) / 16000)) }
        v.onTranscript = { text, ms in
            print(String(format: "transcript (%.0f ms): %@", ms, text))
            if !text.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { v.replyFinished() } }
        }
        Task { @MainActor in
            await v.start()
            v.click()
            try? await Task.sleep(for: .seconds(secs))
            print("mic held during conversation: \(CallDetect.selfCapturing())")
            v.endConversation()
            try? await Task.sleep(for: .milliseconds(300))
            print("mic held after it ended: \(CallDetect.selfCapturing())")
            try? await Task.sleep(for: .milliseconds(500))
            var ru = rusage(); getrusage(RUSAGE_SELF, &ru)
            print(String(format: "cpu %.2f s over the run, max RSS %.0f MB", Double(ru.ru_utime.tv_sec + ru.ru_stime.tv_sec) + Double(ru.ru_utime.tv_usec + ru.ru_stime.tv_usec) / 1e6, Double(ru.ru_maxrss) / 1048576))
            exit(0)
        }
    }
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.run()
}

// MARK: - menu-bar app

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let stateItem = NSMenuItem(title: "Core: starting…", action: nil, keyEquivalent: "")
    private let replyItem = NSMenuItem(title: "No reply yet", action: nil, keyEquivalent: "")
    private let voiceItem = NSMenuItem(title: "Voice: starting…", action: nil, keyEquivalent: "")
    private let voice = VoiceController()
    private var link: CoreLink!
    private var counter = 0

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Zoe ○"
        let menu = NSMenu()
        stateItem.isEnabled = false; replyItem.isEnabled = false; voiceItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(voiceItem)
        menu.addItem(replyItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Start a Conversation", action: #selector(startConversation), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Send a Test Message…", action: #selector(sendTest), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "Restart Core", action: #selector(restartCore), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Zoe", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        startLink()
        voice.onStatus = { [weak self] s in self?.voiceItem.title = "Voice: \(s)"; print("voice: \(s)") }
        voice.onUIState = { [weak self] st in
            guard let self else { return }
            switch st {
            case .idle: self.statusItem.button?.title = "Zoe ●"
            case .listening: self.statusItem.button?.title = "Zoe 🎙"
            case .thinking: self.statusItem.button?.title = "Zoe …"
            case .inCall: self.statusItem.button?.title = "Zoe ☎︎"
            }
        }
        voice.onTranscript = { [weak self] text, ms in
            guard let self, !text.isEmpty else { return }
            self.voiceItem.title = "You: \(text)"
            print(String(format: "transcript (%.0f ms): %@", ms, text))
            self.counter += 1
            self.link.send(CoreMessage("utterance", ["id": "u\(self.counter)", "text": text, "trigger": "ptt"]))
        }
        Task { await voice.start() }
    }

    @objc private func startConversation() { voice.click() }

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
        case "say":
            if let t = m.string("text"), !t.isEmpty { replyItem.title = t }
            // Until Zoe speaks (#5): the reply is done when its final chunk arrives.
            if (m["final"] as? Bool) == true { voice.replyFinished() }
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
