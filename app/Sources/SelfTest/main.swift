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
