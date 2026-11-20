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
                    if texts[turn] == "<<handoff>>" {      // Open in Terminal (not actually opened in smoke mode)
                        link.send(CoreMessage("open_session", ["where": "terminal"]))
                    } else {
                        link.send(CoreMessage("utterance", ["id": "smoke-\(turn + 1)", "text": texts[turn], "trigger": "text"]))
                    }
                } else { done.signal() }
            }
        case "open_terminal":
            print("open_terminal in \(m.string("cwd") ?? "?"): resume \(m.string("session_id") ?? "?")")
        case "session_state":
            print("session_state: \(m.string("session_id") ?? "?") handed_off=\(m["handed_off"] ?? "") forked=\(m["forked"] ?? false)")
            if (m["handed_off"] as? Bool) == true {   // move on to the next scripted line
                turn += 1
                if turn < texts.count {
                    sentAt = Date(); print("> \(texts[turn])")
                    link.send(CoreMessage("utterance", ["id": "smoke-\(turn + 1)", "text": texts[turn], "trigger": "text"]))
                } else { done.signal() }
            }
        case "state": print("assistant: \(m.string("value") ?? "?")")
        case "pending_input":
            // ZOE_SMOKE_ANSWER=approve|deny answers approval cards by "click" (end-to-end gate tests); else deny.
            let id = m.string("id") ?? ""
            if m.string("kind") == "terminal" {
                let c = m["card"] as? [String: Any]
                print("terminal card: \(c?["title"] as? String ?? "?") — \(c?["command"] as? String ?? "?")")
                link.resolveLocally(id)
                return
            }
            if m.string("kind") == "question", let qs = m["questions"] as? [[String: Any]] {
                // Questions: pick each one's first option.
                var answers: [String: String] = [:]
                for q in qs {
                    let first = ((q["options"] as? [[String: Any]])?.first?["label"] as? String) ?? "yes"
                    if let text = q["question"] as? String { answers[text] = first }
                }
                print("question asked: \(qs.count) question(s) → first option(s): \(answers.values.sorted().joined(separator: ", "))")
                link.answer(pendingID: id, value: answers, via: "click")
                return
            }
            let value = ProcessInfo.processInfo.environment["ZOE_SMOKE_ANSWER"] == "approve" ? "approve" : "deny"
            let card = m["card"] as? [String: Any]
            let fields = (card?["fields"] as? [[String: Any]] ?? []).compactMap { f -> String? in
                guard let l = f["label"] as? String, ["To", "Site", "Command"].contains(l) else { return nil }
                return "\(l): \(f["value"] as? String ?? "")"
            }
            print("approval asked: \(card?["title"] as? String ?? "?") [\(fields.joined(separator: "; "))] → \(value)")
            link.answer(pendingID: id, value: value, via: "click")
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

// MARK: - speak test

if let i = args.firstIndex(of: "--speak-test") {
    // Warms up, then speaks the given text sentence by sentence (split on ". "), twice; prints timings.
    let text = i + 1 < args.count ? args[i + 1] : "You have three meetings this afternoon. The first is at two."
    MainActor.assumeIsolated {
        let sp = Speaker()
        Task { @MainActor in
            let warm = await sp.warmUp()
            print(String(format: "voice %@ (%@, quality %d); warm-up %.0f ms", sp.voice.name, sp.voice.identifier, sp.voice.quality.rawValue, warm))
            for run in 1...2 {
                let t0 = ProcessInfo.processInfo.systemUptime
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    sp.onReplyDone = { c.resume() }
                    for s in text.components(separatedBy: ". ") { sp.enqueue(s) }
                    sp.endReply()
                }
                print(String(format: "run %d: first audio %.0f ms (engine start %.0f ms), all played after %.0f ms", run, sp.lastFirstAudioMillis, sp.lastEngineStartMillis, (ProcessInfo.processInfo.systemUptime - t0) * 1000))
            }
            let t0 = ProcessInfo.processInfo.systemUptime
            sp.playAcknowledgement()
            print(String(format: "acknowledgement scheduled in %.1f ms", (ProcessInfo.processInfo.systemUptime - t0) * 1000))
            try? await Task.sleep(for: .seconds(1.5))
            var ru = rusage(); getrusage(RUSAGE_SELF, &ru)
            print(String(format: "cpu %.2f s, max RSS %.0f MB", Double(ru.ru_utime.tv_sec + ru.ru_stime.tv_sec) + Double(ru.ru_utime.tv_usec + ru.ru_stime.tv_usec) / 1e6, Double(ru.ru_maxrss) / 1048576))
            exit(0)
        }
    }
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.run()
}

// MARK: - UI demo

if args.contains("--ui-demo") {
    // Cycles the character through its states with fake levels, shows a bubble and a card, and prints
    // window ids (for `screencapture -l`) and CPU per phase.
    MainActor.assumeIsolated {
        let ch = CharacterWindow()
        let bubble = BubbleWindow(anchor: ch.panel)
        ch.show()
        func cpu() -> Double {
            var ru = rusage(); getrusage(RUSAGE_SELF, &ru)
            return Double(ru.ru_utime.tv_sec + ru.ru_stime.tv_sec) + Double(ru.ru_utime.tv_usec + ru.ru_stime.tv_usec) / 1e6
        }
        Task { @MainActor in
            print("character window \(ch.panel.windowNumber)")
            @MainActor func phase(_ name: String, _ secs: Double, level: Bool = false) async {
                let c0 = cpu(), t0 = Date()
                print("phase \(name)")
                var t = 0.0
                while Date().timeIntervalSince(t0) < secs {
                    if level { ch.level(Float(0.04 + 0.04 * sin(t * 9) * sin(t * 2.3))) }
                    try? await Task.sleep(for: .milliseconds(level ? 50 : 500)); t += level ? 0.05 : 0.5
                }
                print(String(format: "  %@: cpu %.1f %%", name, (cpu() - c0) / secs * 100))
                if let dir = ProcessInfo.processInfo.environment["ZOE_DEMO_SHOTS"], bubble.panel.isVisible,
                   let v = bubble.panel.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)       // the bubble only, never the screen
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/bubble-\(name).png"))
                }
            }
            await phase("idle", 4)
            ch.state = .listening; await phase("listening", 4, level: true)
            bubble.showYou("What's on my calendar this afternoon?")
            ch.state = .thinking; await phase("thinking", 4)
            ch.state = .talking
            bubble.appendReply("You have three meetings this afternoon.")
            bubble.appendReply("The first is a design review at two.")
            bubble.appendReply("Your calendar lists you as a required attendee on every meeting today and tomorrow, and the open office hour is marked as a drop-in because its description says people can stop by.")
            bubble.appendReply("The invite itself doesn't mark you as optional, so I counted it as required.")
            await phase("talking", 4, level: true)
            bubble.showYou("Which pods are failing in the dev cluster?")
            bubble.showFullReply("""
            Two pods are failing, both in the collector service. The details are on screen.

            - **collector-worker-7f9c** is in `CrashLoopBackOff`: it restarted 14 times in the last hour, \
            each time after an out-of-memory kill.
            - **collector-api-5d2b** is `Pending`: no node has enough free memory to schedule it.

            Both point at memory. The worker's limit is 512 Mi and it peaks near 600 Mi during bulk pushes.
            Raising the limit to 1 Gi, or lowering the batch size, should fix the first; the second will \
            schedule once the cluster has room.
            """, summarised: true)
            await phase("card", 4, level: true)
            bubble.showYou("Tell the team the build is green.")
            if let a = ApprovalCard(message: ["id": "demo-1", "voice_ok": true, "card": [
                "title": "Send a Slack message?",
                "fields": [["label": "To", "value": "#team-builds", "mono": false],
                           ["label": "Message", "value": "The build is green again: the flaky test is fixed.", "mono": false]],
                "why": "Sends a message as you."] as [String: Any]]) { bubble.showApproval(a) }
            if let b = ApprovalCard(message: ["id": "demo-2", "voice_ok": false, "card": [
                "title": "Run a command?", "fields": [["label": "Command", "value": "git push origin main", "mono": true]],
                "why": "Runs a command: needs a click."] as [String: Any]]) { bubble.showApproval(b) }
            ch.state = .thinking
            ch.waiting = 2
            await phase("approval", 4)
            bubble.removeApproval("demo-1"); ch.waiting = 1
            await phase("approval2", 3)
            bubble.removeApproval("demo-2"); ch.waiting = 0
            ch.state = .offline; bubble.hide(); await phase("offline", 2)
            ch.state = .idle; await phase("idle-after", 6)
            var ru = rusage(); getrusage(RUSAGE_SELF, &ru)
            print(String(format: "max RSS %.0f MB", Double(ru.ru_maxrss) / 1048576))
            exit(0)
        }
    }
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.run()
}

// MARK: - listen test

if let i = args.firstIndex(of: "--listen-test") {
    let secs = i + 1 < args.count ? Double(args[i + 1]) ?? 12 : 12
    MainActor.assumeIsolated {
        let v = VoiceController()
        v.onStatus = { print("voice: \($0)") }
        v.onUIState = { print("state: \($0)") }
        nonisolated(unsafe) var firstCaption = true
        v.onCaption = { t in if firstCaption { firstCaption = false; print("first caption: \(t)") }; FileHandle.standardError.write(Data("caption: \(t)\n".utf8)) }
        v.onTurn = { s in print(String(format: "turn: %.2f s of audio", Double(s.count) / 16000)) }
        v.onTranscript = { text, ms in
            print(String(format: "transcript (%.0f ms): %@", ms, text))
            guard !text.isEmpty else { return }
            v.turnSent()
            // Stand-in for Claude: reply after 1.5 s (so the acknowledgement plays), in two sentences.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                v.speak("You said: \(text)")
                v.speak("That's all for this test.")
                v.endReply()
                print(String(format: "first sentence → first audio %.0f ms (output engine start %.0f ms)", v.speaker.lastFirstAudioMillis, v.speaker.lastEngineStartMillis))
            }
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
    private var current: String?       // utterance whose reply is being spoken
    private var dropped: String?       // an interrupted reply: its remaining chunks are ignored
    private let character = CharacterWindow()
    private lazy var bubble = BubbleWindow(anchor: character.panel)
    private let characterItem = NSMenuItem(title: "Hide Character", action: #selector(toggleCharacter), keyEquivalent: "h")
    private let terminalItem = NSMenuItem(title: "Open Conversation in Terminal", action: #selector(openConversationInTerminal), keyEquivalent: "o")
    private let takeBackItem = NSMenuItem(title: "Take Back from Terminal", action: #selector(takeBack), keyEquivalent: "")
    private var handedOff = false
    private var coreOffline = false
    private var voiceState: TurnMachine.UIState = .idle

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
        menu.addItem(characterItem)
        menu.addItem(terminalItem)
        menu.addItem(takeBackItem)
        menu.autoenablesItems = false
        takeBackItem.isEnabled = false
        menu.addItem(NSMenuItem(title: "Send a Test Message…", action: #selector(sendTest), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "Restart Core", action: #selector(restartCore), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Zoe", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        startLink()
        voice.onStatus = { [weak self] s in self?.voiceItem.title = "Voice: \(s)"; print("voice: \(s)") }
        character.onClick = { [weak self] in
            guard let self else { return }
            // Something waits but its card isn't on screen: bring it back instead of starting to listen (#21).
            if self.bubble.waiting > 0 && !self.bubble.isVisible { self.bubble.relayout(); return }
            self.voice.click()
        }
        bubble.onWaitingChanged = { [weak self] n in self?.character.waiting = n }
        character.onMove = { [weak self] in self?.bubble.relayout() }
        character.show()
        voice.onMicLevel = { [weak self] v in self?.character.level(v) }
        voice.speaker.onLevel = { [weak self] v in self?.character.level(v) }
        voice.onReplyDone = { [weak self] in self?.bubble.replyDone() }
        voice.onCaption = { [weak self] t in self?.bubble.showCaption(t) }
        bubble.onAnswer = { [weak self] id, approved in
            guard let self else { return }
            self.link.answer(pendingID: id, value: approved ? "approve" : "deny", via: "click")
            self.bubble.removeApproval(id)
            self.voice.approvalClosed(id: id)
            print("[metrics] approval \(approved ? "approved" : "denied") by click")
        }
        bubble.onQuestionAnswered = { [weak self] id, answers in
            guard let self else { return }
            self.link.answer(pendingID: id, value: answers, via: "click")
            self.voice.approvalClosed(id: id)
        }
        voice.onQuestionAnswer = { [weak self] id, question, value in
            guard let self else { return }
            self.link.answer(pendingID: id, value: [question: value], via: "voice")
            self.bubble.removeQuestion(id)
            self.voice.approvalClosed(id: id)
            self.voice.speak("Okay.")
        }
        bubble.onHandOff = { [weak self] in self?.openConversationInTerminal() }
        bubble.onRunInTerminal = { [weak self] card in
            guard let self, let t = card.terminal else { return }
            self.link.answer(pendingID: card.id, value: "deny", via: "terminal")   // Zoe doesn't run it
            self.bubble.removeApproval(card.id)
            self.voice.approvalClosed(id: card.id)
            self.openInTerminal(command: t.command, cwd: t.cwd)
        }
        bubble.onTerminalDone = { [weak self] card, open in
            guard let self else { return }
            self.link.resolveLocally(card.id)
            if open { self.openInTerminal(command: card.command, cwd: card.cwd) }
        }
        voice.onApprovalAnswer = { [weak self] id, approved in
            guard let self else { return }
            self.link.answer(pendingID: id, value: approved ? "approve" : "deny", via: "voice")
            self.bubble.removeApproval(id)
            self.voice.approvalClosed(id: id)
            self.voice.speak(approved ? "Okay." : "Okay, I won't.")
        }
        voice.onUIState = { [weak self] st in
            guard let self else { return }
            self.voiceState = st
            self.updateCharacter()
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
            self.bubble.showYou(text)
            print(String(format: "transcript (%.0f ms): %@", ms, text))
            self.counter += 1
            self.current = "u\(self.counter)"
            self.link.send(CoreMessage("utterance", ["id": self.current!, "text": text, "trigger": "ptt"]))
            self.voice.turnSent()
        }
        voice.onListeningStarted = { [weak self] in self?.link.send(CoreMessage("listening")) }
        voice.onInterrupt = { [weak self] in
            guard let self, let id = self.current else { return }
            self.dropped = id            // ignore the rest of the interrupted reply
            self.link.send(CoreMessage("user_interrupted", ["utterance_id": id]))
        }
        Task { await voice.start() }
    }

    @objc private func startConversation() { voice.click() }

    /// Runs a command in a new Terminal window, in its folder (#19, #20).
    func openInTerminal(command: String, cwd: String) {
        do {
            let url = try TerminalScript.write(command: command, cwd: cwd)
            let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            // Zoe never takes focus, so macOS won't let it bring another app forward unless it hands focus over:
            // become active for a moment, yield to Terminal, and ask Terminal forward once it has the window.
            NSApp.activate()
            NSApp.yieldActivation(toApplicationWithBundleIdentifier: "com.apple.Terminal")
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: terminal, configuration: cfg) { app, error in
                if let error { print("couldn't open Terminal: \(error)"); return }
                DispatchQueue.main.async { _ = app?.activate(from: .current, options: []) }
            }
            print("[metrics] opened in Terminal")
        } catch {
            print("couldn't open Terminal: \(error)")
        }
    }

    /// Hands the conversation to Terminal (`claude --resume`), so Zoe stops writing to it (#20).
    @objc private func openConversationInTerminal() {
        link.send(CoreMessage("open_session", ["where": "terminal"]))
    }

    /// Talk to Zoe again about the handed-off conversation: the core forks it.
    @objc private func takeBack() {
        link.send(CoreMessage("take_back"))
        takeBackItem.isEnabled = false
    }

    @objc private func toggleCharacter() {
        if character.isVisible { character.hide(); bubble.hide(); characterItem.title = "Show Character" }
        else { character.show(); characterItem.title = "Hide Character" }
    }

    /// Character state from the turn machine, the core link, and whether Zoe is talking.
    private func updateCharacter(talking: Bool = false) {
        if coreOffline { character.state = .offline; return }
        switch voiceState {
        case .idle: character.state = .idle
        case .listening: character.state = .listening
        case .thinking: character.state = talking ? .talking : .thinking
        case .inCall: character.state = .inCall
        }
    }

    private func startLink() {
        link = CoreLink(command: .auto(developmentCoreDir: coreDirectory()))
        link.onLog = { FileHandle.standardError.write(Data($0.utf8)) }
        link.onState = { [weak self] s in MainActor.assumeIsolated { self?.show(s) } }
        link.onMessage = { [weak self] m in MainActor.assumeIsolated { self?.handle(m) } }
        link.onPendingDenied = { [weak self] ids in
            MainActor.assumeIsolated {
                for id in ids { self?.bubble.removeApproval(id); self?.bubble.removeQuestion(id); self?.voice.approvalClosed(id: id) }
            }
            print("core restarted: denied \(ids.count) pending approval(s)")
        }
        link.start()
    }

    private func show(_ s: LinkState) {
        switch s {
        case .starting: stateItem.title = "Core: starting…"; statusItem.button?.title = "Zoe ○"
        case .ready(let pid): stateItem.title = "Core: ready (pid \(pid))"; statusItem.button?.title = "Zoe ●"
        case .offline(let why): stateItem.title = "Core: offline — \(why)"; statusItem.button?.title = "Zoe ⊘"
        case .stopped: stateItem.title = "Core: stopped"; statusItem.button?.title = "Zoe ○"
        }
        if case .offline = s { coreOffline = true } else { coreOffline = false }
        updateCharacter()
        print("core state: \(s)")
    }

    private func handle(_ m: CoreMessage) {
        switch m.type {
        case "say":
            if let id = m.string("utterance_id"), id == dropped { return }
            if let t = m.string("text"), !t.isEmpty { replyItem.title = t; voice.speak(t); bubble.appendReply(t) }
            if (m["final"] as? Bool) == true { voice.endReply() }
        case "open_terminal":
            if let cmd = m.string("command") {
                openInTerminal(command: cmd, cwd: m.string("cwd") ?? "")
                voice.endConversation()
            }
        case "session_state":
            handedOff = (m["handed_off"] as? Bool) == true
            takeBackItem.isEnabled = handedOff
            if (m["forked"] as? Bool) == true { print("[metrics] handed-off conversation forked") }
        case "pending_input" where m.string("kind") == "terminal":
            guard let t = TerminalCard(message: m.fields) else { return }
            bubble.showTerminal(t)
            NSSound(named: "Glass")?.play()
        case "pending_input" where m.string("kind") == "question":
            guard let q = QuestionCard(message: m.fields) else { return }
            bubble.showQuestion(q)
            NSSound(named: "Glass")?.play()
            let first = q.questions[0]
            voice.questionAsked(id: q.id, question: first.text, labels: first.options.map(\.label), multi: first.multi,
                                voiceOK: q.questions.count == 1)
        case "pending_input":
            guard m.string("kind") == "approval", let card = ApprovalCard(message: m.fields) else { return }
            bubble.showApproval(card)
            NSSound(named: "Glass")?.play()           // something needs me
            let summary = (m["card"] as? [String: Any])?["summary"] as? String ?? card.title
            voice.approvalAsked(id: card.id, summary: summary, voiceOK: card.voiceOK)
        case "dismiss_panel":
            if let id = m.string("id") { bubble.removeApproval(id); bubble.removeQuestion(id); bubble.removeTerminal(id); voice.approvalClosed(id: id) }
        case "bubble":
            if let id = m.string("utterance_id"), id == dropped { return }
            bubble.showFullReply(m.string("text") ?? "", summarised: (m["summarised"] as? Bool) == true)
        case "state":
            if m.string("value") == "talking" { updateCharacter(talking: true) }
            print("assistant state: \(m.string("value") ?? "?")")
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
        current = "u\(counter)"
        bubble.showYou(field.stringValue)
        link.send(CoreMessage("utterance", ["id": current!, "text": field.stringValue, "trigger": "text"]))
    }

    @objc private func restartCore() { link.stop(); startLink() }
    @objc private func quit() { link.stop(); NSApp.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
