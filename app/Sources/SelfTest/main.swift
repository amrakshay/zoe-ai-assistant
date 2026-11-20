// zoe-selftest: plain-executable test suite (Swift Testing / XCTest need full Xcode).
// Prints one line per check and `ALL CHECKS PASSED` at the end; exits 1 on any failure.
import Foundation
import ZoeKit

setvbuf(stdout, nil, _IOLBF, 0)
nonisolated(unsafe) var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    print(ok ? "  ok   \(name)" : "  FAIL \(name) \(detail())")
    if !ok { failures += 1 }
}
func data(_ s: String) -> Data { Data(s.utf8) }

// MARK: framing
print("JSON-lines framing")
do {
    var f = JSONLineFramer()
    check("partial line waits for its newline", f.feed(data(#"{"type":"pi"#)).isEmpty)
    let r = f.feed(data(#"ng","id":1}"# + "\n"))
    check("partial line completes", r.count == 1 && (try? r[0].get())?.type == "ping")

    let burst = f.feed(data(#"{"type":"a"}"# + "\n" + #"{"type":"b"}"# + "\n\n  \n" + #"{"type":"c"}"# + "\n"))
    check("burst of lines, blanks ignored", burst.compactMap { try? $0.get().type } == ["a", "b", "c"])

    let bad = f.feed(data("not json\n[1]\n" + #"{"x":1}"# + "\n" + #"{"type":"ok"}"# + "\n"))
    let errs = bad.filter { if case .failure = $0 { return true } else { return false } }
    check("bad lines are errors and don't stop the stream", errs.count == 3 && (try? bad.last!.get())?.type == "ok")

    var g = JSONLineFramer()
    let big = g.feed(Data(repeating: 0x61, count: JSONLineFramer.maxLine + 10))
    check("over-long line is rejected", big.count == 1)
    let after = g.feed(data("tail of the long line\n" + #"{"type":"next"}"# + "\n"))
    check("stream recovers after an over-long line", after.compactMap { try? $0.get().type } == ["next"])

    let m = CoreMessage("say", ["text": "two\nlines"])
    let enc = try! m.encoded()
    check("encoded message is exactly one line", enc.filter { $0 == 0x0A }.count == 1 && enc.last == 0x0A)
    var h = JSONLineFramer()
    check("round trip", (try? h.feed(enc)[0].get()) == m)
}

// MARK: turn-taking
print("Turn-taking (push-to-talk / click)")
do {
    typealias E = TurnMachine.Event
    func run(_ events: [E]) -> (TurnMachine, [[TurnMachine.Action]]) {
        var m = TurnMachine()
        let actions = events.map { m.handle($0) }
        return (m, actions)
    }
    let start: [TurnMachine.Action] = [.chime(.start), .startEngine, .setState(.listening)]
    let end: [TurnMachine.Action] = [.chime(.end), .stopEngine, .setState(.idle)]

    // Hold from idle: listen at once, release sends one turn, reply ends the conversation.
    var (m, a) = run([.keyDown(0), .speechStart(0.3), .keyUp(2), .replyFinished(5)])
    check("hold: starts listening on key down", a[0] == start)
    check("hold: release sends the turn", a[2] == [.endTurn, .setState(.thinking)])
    check("hold: reply ends the conversation, mic released", a[3] == end && m.phase == .idle)

    (m, a) = run([.keyDown(0), .keyUp(1)])
    check("hold with no speech: nothing sent, conversation ends", a[1] == [.discardTurn] + end && m.phase == .idle)

    // Tap from idle: hands-free; VAD ends turns; follow-ups; silence timeout ends it.
    (m, a) = run([.keyDown(0), .keyUp(0.1), .speechStart(1), .speechEnd(3), .replyFinished(6),
                  .speechStart(7), .speechEnd(8), .replyFinished(10), .tick(29), .tick(30.5)])
    check("tap: becomes hands-free, engine already on", a[1] == [] && a[0] == start)
    check("tap: VAD end of speech sends the turn", a[3] == [.endTurn, .setState(.thinking)])
    check("tap: listens again after the reply", a[4] == [.setState(.listening)])
    check("tap: follow-up turn", a[6] == [.endTurn, .setState(.thinking)])
    check("tap: no timeout before 20 s of silence", a[8] == [])
    check("tap: 20 s of silence ends it", a[9] == [.discardTurn] + end && m.phase == .idle)

    (m, a) = run([.click(0), .speechStart(1), .speechEnd(2), .click(3)])
    check("click starts hands-free", a[0] == start)
    check("click while waiting stops the reply and ends the conversation", a[3] == [.interruptReply] + end && m.phase == .idle)

    (m, a) = run([.keyDown(0), .speechStart(0.3), .keyUp(2), .keyDown(4), .speechStart(4.2), .keyUp(6), .replyFinished(9)])
    check("key during a reply interrupts it and listens", a[3] == [.interruptReply, .setState(.listening)] && m.phase == .idle)
    check("…the held key sends a new turn", a[5] == [.endTurn, .setState(.thinking)])
    check("…and its reply ends the conversation (the app drops the interrupted reply's end)", a[6] == end)

    (m, a) = run([.click(0), .speechStart(1), .speechEnd(2), .keyDown(4), .keyUp(4.1)])
    check("tap during a hands-free reply: interrupts and keeps listening", a[3] == [.interruptReply, .setState(.listening)] && a[4] == [.discardTurn] && m.phase == .listening(.handsFree))

    (m, a) = run([.keyDown(0), .keyUp(0.1), .keyDown(5), .keyUp(5.1)])
    check("tap during a conversation ends it", a[3] == [.discardTurn] + end && m.phase == .idle)

    (m, a) = run([.click(0), .keyDown(5), .speechStart(5.2), .keyUp(7), .replyFinished(9)])
    check("hold during a conversation is a turn inside it", a[3] == [.endTurn, .setState(.thinking)])
    check("…and the conversation continues after the reply", a[4] == [.setState(.listening)] && m.phase == .listening(.handsFree))

    (m, a) = run([.click(0), .callStarted, .keyDown(2), .click(3), .callEnded, .keyDown(10)])
    check("a call stops the conversation and the engine", a[1] == [.discardTurn, .stopEngine, .setState(.inCall)])
    check("triggers are refused during a call", a[2] == [.refuse("in a call")] && a[3] == [.refuse("in a call")])
    check("after the call, the hotkey works again", a[5] == start)

    (m, a) = run([.keyDown(0), .keyCancelled(0.2)])
    check("right ⌥ used as a modifier: cancelled, nothing sent", a[1] == [.discardTurn] + end && m.phase == .idle)
    (m, a) = run([.click(0), .keyDown(3), .keyCancelled(3.1)])
    check("…inside a conversation: back to hands-free", a[2] == [.discardTurn] && m.phase == .listening(.handsFree))

    (m, a) = run([.click(0), .speechStart(1), .endConversationRequested(2)])
    check("the core can end the conversation (\"bye\")", a[2] == [.discardTurn] + end)
}

// MARK: VAD
print("Silero VAD (model downloaded and checksum-verified on first run)")
do {
    func blocking<T: Sendable>(_ f: @escaping @Sendable () async throws -> T) throws -> T {
        nonisolated(unsafe) var r: Result<T, Error>!
        let s = DispatchSemaphore(value: 0)
        Task.detached { do { r = .success(try await f()) } catch { r = .failure(error) }; s.signal() }
        s.wait(); return try r.get()
    }
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("zoe-selftest-\(getpid())")
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    do {
        let model = try blocking { try await ModelStore.path(for: .sileroVAD) }
        let vad = try SileroVAD(modelPath: model)
        let aiff = tmp.appendingPathComponent("speech.aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", aiff.path, "Hello Zoe, what's on my calendar this afternoon?"]
        try say.run(); say.waitUntilExit()
        let speech = try Resampler.load(aiff)
        check("speech file resampled to 16 kHz", speech.count > 16000, "\(speech.count) samples")
        let lead = [Float](repeating: 0, count: 16000), tail = [Float](repeating: 0, count: 32000)
        let audio = lead + speech + tail
        var seg = SpeechSegmenter()
        var events: [SpeechSegmenter.Event] = []
        let t0 = Date()
        var i = 0
        while i + SileroVAD.window <= audio.count {
            let p = try vad.probability(audio[i..<(i + SileroVAD.window)])
            i += SileroVAD.window
            if let e = seg.feed(probability: p, at: Double(i) / 16000) { events.append(e) }
        }
        let perWindow = Date().timeIntervalSince(t0) / Double(audio.count / SileroVAD.window) * 1000
        let speechEnd = 1 + Double(speech.count) / 16000
        if case .start(let s)? = events.first { check("speech start found near 1 s", s > 0.7 && s < 1.6, "start \(s)") }
        else { check("speech start found", false, "\(events)") }
        if events.count == 2, case .end(let e) = events[1] {
            check("speech end found after the phrase", e > speechEnd - 0.6 && e < speechEnd + 0.6, "end \(e), phrase ends \(speechEnd)")
        } else { check("exactly one start and one end", false, "\(events)") }
        check(String(format: "VAD cost %.2f ms per 32 ms window", perWindow), perWindow < 3)
        vad.reset(); var quiet = SpeechSegmenter(); var fired = false
        var noise = [Float](repeating: 0, count: 16000 * 3)
        for k in noise.indices { noise[k] = Float.random(in: -0.003...0.003) }
        for j in stride(from: 0, to: noise.count - SileroVAD.window, by: SileroVAD.window) {
            if quiet.feed(probability: try vad.probability(noise[j..<(j + SileroVAD.window)]), at: Double(j) / 16000) != nil { fired = true }
        }
        check("no speech found in 3 s of faint noise", !fired)
    } catch {
        check("VAD runs", false, "\(error)")
    }
}

// MARK: voice answers to approval cards (#17)
print("Voice answers")
do {
    let yes = ["Yes", "yes.", "Yeah, go ahead", "Sure", "OK", "okay do it", "Send it", "Sounds good!", "Approve"]
    let no = ["No", "nope", "Cancel that", "Don't", "Yes, cancel it", "wait", "no, don't send it", "Okay no"]
    let unclear = ["", "Hmm", "maybe", "What does it say?", "yes please send it to the whole company right now",
                   "Change the message first"]
    check("yes answers", yes.allSatisfy { VoiceAnswer.classify($0) == .yes }, "\(yes.filter { VoiceAnswer.classify($0) != .yes })")
    check("no answers, and a no anywhere wins", no.allSatisfy { VoiceAnswer.classify($0) == .no }, "\(no.filter { VoiceAnswer.classify($0) != .no })")
    check("anything else is unclear", unclear.allSatisfy { VoiceAnswer.classify($0) == .unclear }, "\(unclear.filter { VoiceAnswer.classify($0) != .unclear })")
    check("speech that began during the prompt doesn't count", !VoiceAnswer.accepted(speechStart: 9.95, promptEnd: 10))
    check("…nor within the echo tail", !VoiceAnswer.accepted(speechStart: 10.05, promptEnd: 10))
    check("speech after the prompt counts", VoiceAnswer.accepted(speechStart: 10.3, promptEnd: 10))
}

// MARK: spoken answers to Claude's questions (#19)
print("Option matching")
do {
    let l = ["Summary", "Detailed report", "Skip"]
    check("a label said in a sentence", OptionMatch.match("Detailed report, please", labels: l, multiSelect: false) == ["Detailed report"])
    check("case and punctuation don't matter", OptionMatch.match("summary!", labels: l, multiSelect: false) == ["Summary"])
    check("ordinals pick by position", OptionMatch.match("the second one", labels: l, multiSelect: false) == ["Detailed report"])
    check("'last' picks the last", OptionMatch.match("the last", labels: l, multiSelect: false) == ["Skip"])
    check("two labels for a single choice is ambiguous", OptionMatch.match("summary or skip", labels: l, multiSelect: false) == [])
    check("multi-select takes every label said", OptionMatch.match("summary and skip", labels: l, multiSelect: true) == ["Summary", "Skip"])
    check("'both' / 'all' in multi-select", OptionMatch.match("all of them", labels: l, multiSelect: true) == l)
    check("a partial label isn't a match", OptionMatch.match("detailed", labels: l, multiSelect: false) == [])
    check("no match → [] (sent as typed text)", OptionMatch.match("something else entirely", labels: l, multiSelect: false) == [])
}

// MARK: Open in Terminal scripts (#19)
print("Terminal scripts")
do {
    check("quoting survives quotes", TerminalScript.quote("it's") == "'it'\\''s'")
    let s = TerminalScript.script(command: "sudo true", cwd: "/tmp/a b'c")
    check("goes to the folder, quoted", s.contains("cd '/tmp/a b'\\''c'"))
    check("runs exactly the command", s.contains("\nsudo true\n"))
    check("clears inherited Claude Code variables first", s.contains("unset -m 'CLAUDE*' 'ANTHROPIC*'"))
    check("empty folder → home", TerminalScript.script(command: "claude", cwd: "").contains("cd $HOME"))
    let url = try TerminalScript.write(command: "echo hi", cwd: "/tmp")
    let p = (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
    check("written as a private .command file", url.pathExtension == "command" && p == 0o700)
    // It must parse as zsh.
    let z = Process(); z.executableURL = URL(fileURLWithPath: "/bin/zsh"); z.arguments = ["-n", url.path]
    try z.run(); z.waitUntilExit()
    check("the script parses (zsh -n)", z.terminationStatus == 0)
    try? FileManager.default.removeItem(at: url)
} catch {
    check("terminal script", false, "\(error)")
}

// MARK: supervision with a fake core
print("Core link supervision")
let fakeCore = """
import sys, json, os
for line in sys.stdin:
    m = json.loads(line)
    t = m["type"]
    if t == "hello": print(json.dumps({"type": "hello", "pid": os.getpid()}), flush=True)
    elif t == "ping": print(json.dumps({"type": "pong", "id": m.get("id")}), flush=True)
    elif t == "ask": print(json.dumps({"type": "pending_input", "id": m["id"], "kind": "approval", "card": {}}), flush=True)
    elif t == "withdraw": print(json.dumps({"type": "dismiss_panel", "id": m["id"]}), flush=True)
    elif t == "answer": print(json.dumps({"type": "answered", "pending_id": m["pending_id"], "value": m["value"], "via": m["via"]}), flush=True)
    elif t == "crash": os._exit(3)
    elif t == "shutdown": break
"""
final class Box: @unchecked Sendable {
    let lock = NSLock()
    var states: [LinkState] = []
    var messages: [CoreMessage] = []
    var denied: [String] = []
}
let box = Box()
let cbq = DispatchQueue(label: "selftest.callbacks")
let link = CoreLink(command: CoreCommand(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: ["python3", "-u", "-c", fakeCore]),
                    callbackQueue: cbq)
link.onState = { s in box.lock.withLock { box.states.append(s) } }
link.onMessage = { m in box.lock.withLock { box.messages.append(m) } }
link.onPendingDenied = { ids in box.lock.withLock { box.denied += ids } }

func waitFor(_ timeout: TimeInterval, _ cond: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end { if cond() { return true }; Thread.sleep(forTimeInterval: 0.02) }
    return cond()
}
func readyCount() -> Int { box.lock.withLock { box.states.filter { if case .ready = $0 { return true } else { return false } }.count } }

let t0 = Date()
link.start()
check("core starts and answers hello", waitFor(5) { readyCount() == 1 }, "states: \(box.states)")
print(String(format: "       (spawn → ready %.0f ms)", Date().timeIntervalSince(t0) * 1000))
link.send(CoreMessage("ping", ["id": 42]))
check("ping → pong", waitFor(2) { box.lock.withLock { box.messages.contains { $0.type == "pong" && ($0["id"] as? Int) == 42 } } })

for id in ["approval-1", "approval-2", "approval-3", "approval-4"] { link.send(CoreMessage("ask", ["id": id])) }
check("pending_input is recorded as waiting", waitFor(2) { link.pending.count == 4 })
link.send(CoreMessage("withdraw", ["id": "approval-3"]))
check("dismiss_panel withdraws it", waitFor(2) { link.pending.count == 3 })
link.answer(pendingID: "approval-4", value: "approve", via: "click")
check("my answer reaches the core and is no longer pending",
      waitFor(2) { box.lock.withLock { box.messages.contains { $0.type == "answered" && $0.string("pending_id") == "approval-4" && $0.string("value") == "approve" } } }
      && link.pending.count == 2)
let crashAt = Date()
link.send(CoreMessage("crash"))
check("crash is reported as offline", waitFor(2) { box.lock.withLock { box.states.contains { if case .offline = $0 { return true } else { return false } } } })
check("core restarts within 2 s", waitFor(2) { readyCount() == 2 }, "states: \(box.states)")
print(String(format: "       (crash → ready again %.0f ms)", Date().timeIntervalSince(crashAt) * 1000))
check("pending approvals are denied on restart", box.lock.withLock { box.denied == ["approval-1", "approval-2"] } && link.pending.count == 0)
check("restart counted", link.restarts == 1)

link.stop()
check("stop ends in .stopped, no restart", waitFor(3) { box.lock.withLock { box.states.last == .stopped } } && readyCount() == 2)

print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
