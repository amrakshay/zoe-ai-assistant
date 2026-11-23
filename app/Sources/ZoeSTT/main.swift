// zoe-stt: runs Whisper for the app in its own process (#41). Protocol: STTWire.swift.
//
//     zoe-stt --models <dir>
//
// The app starts it when a conversation starts and closes its stdin a while after the conversation ends,
// so Whisper's ~185 MB is only in memory while it can be used. Its memory still counts towards Zoe's
// budget (PLAN.md §12.2: app + helper). Living in a binary that rarely changes means Core ML's Neural
// Engine compile of the model (about two minutes) survives app rebuilds.
import Darwin
import Foundation
import STTWire
@preconcurrency import WhisperKit

// stdout is the protocol. Keep a private copy of it and point fd 1 at stderr, so nothing a library prints
// can corrupt a reply.
enum Out {
    nonisolated(unsafe) static var fd: Int32 = STDOUT_FILENO   // set once below, before any reply
    static let lock = NSLock()
}
Out.fd = dup(STDOUT_FILENO)
dup2(STDERR_FILENO, STDOUT_FILENO)
signal(SIGPIPE, SIG_IGN)

@Sendable func reply(_ r: STTWire.Reply) {
    let d = STTWire.line(r)
    let ok = Out.lock.withLock { writeAll(Out.fd, d) }
    if !ok { exit(0) }   // the app is gone
}

func log(_ s: String) { FileHandle.standardError.write(Data("zoe-stt: \(s)\n".utf8)) }

var modelsDir: URL?
var argv = CommandLine.arguments.dropFirst()
while let a = argv.popFirst() {
    if a == "--models", let v = argv.popFirst() { modelsDir = URL(fileURLWithPath: v) }
}
guard let base = modelsDir?.appendingPathComponent("whisper") else {
    log("usage: zoe-stt --models <dir>")
    exit(2)
}

/// WhisperKit isn't Sendable; it's only used inside this actor.
actor Engine {
    private let base: URL
    private var kit: WhisperKit?
    init(base: URL) { self.base = base }

    func load(progress: @escaping @Sendable (Double) -> Void) async throws -> Double? {
        if kit != nil { return nil }
        let t0 = Date()
        let folder = base.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(STTWire.variant)")
        if !FileManager.default.fileExists(atPath: folder.appendingPathComponent("AudioEncoder.mlmodelc").path) {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            _ = try await WhisperKit.download(variant: STTWire.variant, downloadBase: base) { p in
                progress(p.fractionCompleted)
            }
        }
        let cfg = WhisperKitConfig(model: STTWire.variant, downloadBase: base, modelFolder: folder.path,
                                   verbose: false, logLevel: .error, prewarm: false, load: true, download: false)
        kit = try await WhisperKit(cfg)
        return Date().timeIntervalSince(t0) * 1000
    }

    func transcribe(_ samples: [Float]) async throws -> (String, Double) {
        _ = try await load { _ in }
        guard let kit else { throw CocoaError(.featureUnsupported) }
        let t0 = Date()
        let opts = DecodingOptions(task: .transcribe, language: "en", temperature: 0, usePrefillPrompt: true,
                                   skipSpecialTokens: true, withoutTimestamps: true)
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: opts)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return (text, Date().timeIntervalSince(t0) * 1000)
    }
}

/// Physical footprint (what Activity Monitor calls Memory) and peak RSS of this process, in MB.
func memoryStats() -> (footprint: Double, maxRSS: Double) {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    var ru = rusage(); getrusage(RUSAGE_SELF, &ru)
    return (kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0, Double(ru.ru_maxrss) / 1_048_576)
}

let engine = Engine(base: base)
let input = FDReader(fd: STDIN_FILENO)

while let line = input.readLine() {
    guard let req = STTWire.decode(STTWire.Request.self, line) else {
        reply(.init(event: "error", error: "bad request"))
        continue
    }
    switch req.op {
    case "load":
        do {
            let ms = try await engine.load { p in reply(.init(event: "progress", progress: p)) }
            reply(.init(event: "loaded", millis: ms ?? 0))
        } catch { reply(.init(event: "error", error: "\(error)")) }
    case "transcribe":
        let n = req.samples ?? -1
        guard n >= 0, n <= STTWire.maxSamples else { log("bad frame size \(n)"); exit(3) }   // can't resync
        guard let bytes = input.read(exactly: n * 4) else { exit(0) }
        do {
            let (text, ms) = try await engine.transcribe(STTWire.samples(from: bytes))
            reply(.init(event: "text", text: text, millis: ms))
        } catch { reply(.init(event: "error", error: "\(error)")) }
    case "stats":
        let m = memoryStats()
        reply(.init(event: "stats", footprintMB: m.footprint, maxRSSMB: m.maxRSS))
    default:
        reply(.init(event: "error", error: "unknown op \(req.op)"))
    }
}
exit(0)   // stdin closed: the app unloaded Whisper, or quit
