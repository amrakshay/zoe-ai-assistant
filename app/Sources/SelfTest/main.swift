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
    check("click while waiting ends the conversation", a[3] == end && m.phase == .idle)

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

// MARK: supervision with a fake core
print("Core link supervision")
let fakeCore = """
import sys, json, os
for line in sys.stdin:
    m = json.loads(line)
    t = m["type"]
    if t == "hello": print(json.dumps({"type": "hello", "pid": os.getpid()}), flush=True)
    elif t == "ping": print(json.dumps({"type": "pong", "id": m.get("id")}), flush=True)
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

link.pending.add("approval-1"); link.pending.add("approval-2")
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
