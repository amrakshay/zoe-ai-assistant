import CryptoKit
import Foundation
import STTWire

/// Speech-to-text for the final transcript of each turn (#4): Whisper large-v3-turbo via WhisperKit,
/// **no prompt** (F04 addendum 3: a term prompt didn't improve intent, added ~0.4 s and could leak into
/// the output).
///
/// Whisper runs in `zoe-stt`, a helper process next to the app's executable (#41). `load()` starts it
/// when a conversation starts — while I'm still speaking — and `unload()` ends it a while after, so the
/// model (~1.5 GB on disk, ~185 MB in memory) isn't in memory when Zoe is idle. The helper's memory is
/// part of Zoe's footprint and is budgeted with the app's (PLAN.md §12.2).
public actor WhisperSTT {
    public static let variant = STTWire.variant
    public let modelsDirectory: URL
    public var downloadBase: URL { modelsDirectory.appendingPathComponent("whisper") }
    public let helperURL: URL

    private var helper: STTHelper?
    private var loading: Task<(STTHelper, Double, Double), Error>?
    private var generation = 0
    /// Helper start + model load, as seen by the app (what a turn waits for after an idle exit).
    public private(set) var lastLoadMillis: Double = 0
    /// The model load alone, measured inside the helper (the rest of `lastLoadMillis` is process start-up).
    public private(set) var lastModelLoadMillis: Double = 0

    public init(modelsDirectory: URL = ModelStore.directory, helperURL: URL = WhisperSTT.defaultHelperURL) {
        self.modelsDirectory = modelsDirectory
        self.helperURL = helperURL
    }

    /// `zoe-stt` next to the running executable: `Zoe.app/Contents/MacOS/` in the bundle, `.build/<config>/`
    /// in development (`swift build` builds it; `swift run Zoe` alone doesn't). `$ZOE_STT_HELPER` overrides.
    public static var defaultHelperURL: URL {
        if let p = ProcessInfo.processInfo.environment["ZOE_STT_HELPER"] { return URL(fileURLWithPath: p) }
        let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        return exe.resolvingSymlinksInPath().deletingLastPathComponent().appendingPathComponent("zoe-stt")
    }

    public var isLoaded: Bool { helper?.isRunning == true }
    /// The helper's process id while it runs (for measuring).
    public var helperPID: Int32? { helper?.isRunning == true ? helper?.pid : nil }

    /// Core ML compiles the model for the Neural Engine on the first load (measured: 113–157 s, 17 s CPU,
    /// 1.4 GB peak); later loads take about 1.1 s. The compile is cached per macOS build and binary, so it
    /// happened again after every app rebuild while Whisper ran in the app; the helper rarely changes. A
    /// marker per model, macOS build and helper binary records that the compile has happened, so it runs
    /// at launch rather than in the first conversation.
    private var preparedMarker: URL {
        let os = ProcessInfo.processInfo.operatingSystemVersionString.filter { $0.isLetter || $0.isNumber }
        return downloadBase.appendingPathComponent(".prepared-\(Self.variant)-\(os)-\(helperStamp)")
    }
    private lazy var helperStamp: String = {
        guard let d = try? Data(contentsOf: helperURL, options: .mappedIfSafe) else { return "missing" }
        return SHA256.hash(data: d).prefix(8).map { String(format: "%02x", $0) }.joined()
    }()
    public var isPrepared: Bool { FileManager.default.fileExists(atPath: preparedMarker.path) }

    /// Starts the helper and loads the model (downloading it on first use). Safe to call repeatedly.
    public func load(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        _ = try await ensureHelper(progress: progress)
    }

    private func ensureHelper(progress: (@Sendable (Double) -> Void)? = nil) async throws -> STTHelper {
        if let helper, helper.isRunning { return helper }
        helper = nil
        if let loading { return try await loading.value.0 }
        let gen = generation
        let (exe, models) = (helperURL, modelsDirectory)
        let t = Task { () throws -> (STTHelper, Double, Double) in
            let t0 = Date()
            let h = try STTHelper.launch(executable: exe, modelsDirectory: models)
            do {
                let r = try await h.call(STTWire.line(STTWire.Request(op: "load")), progress: progress)
                return (h, Date().timeIntervalSince(t0) * 1000, r.millis ?? 0)
            } catch { h.close(); throw error }
        }
        loading = t
        do {
            let (h, total, model) = try await t.value
            guard generation == gen else { h.close(); throw CancellationError() }   // unloaded meanwhile
            helper = h; loading = nil
            lastLoadMillis = total; lastModelLoadMillis = model
            if !isPrepared { FileManager.default.createFile(atPath: preparedMarker.path, contents: nil) }
            return h
        } catch {
            if generation == gen { loading = nil }
            throw error
        }
    }

    public struct Result: Sendable {
        public let text: String
        public let millis: Double
        public init(text: String, millis: Double) { self.text = text; self.millis = millis }
    }

    /// Transcribes 16 kHz mono samples. Returns trimmed text ("" if nothing was said). `millis` is Whisper's
    /// own time in the helper; the round trip adds well under a millisecond per second of audio (measured).
    /// If the helper died, it is started again once.
    public func transcribe(_ samples: [Float]) async throws -> Result {
        let frame = STTWire.transcribeFrame(samples)
        do {
            let r = try await ensureHelper().call(frame)
            return Result(text: Self.clean(r.text ?? ""), millis: r.millis ?? 0)
        } catch STTError.helperExited {
            helper = nil
            let r = try await ensureHelper().call(frame)
            return Result(text: Self.clean(r.text ?? ""), millis: r.millis ?? 0)
        }
    }

    /// The helper's physical footprint and peak RSS in MB (nil when it isn't running).
    public func helperMemory() async -> (footprintMB: Double, maxRSSMB: Double)? {
        guard let helper, helper.isRunning,
              let r = try? await helper.call(STTWire.line(STTWire.Request(op: "stats"))) else { return nil }
        return (r.footprintMB ?? 0, r.maxRSSMB ?? 0)
    }

    /// Ends the helper, which frees all of Whisper's memory.
    public func unload() async {
        generation += 1
        loading = nil
        helper?.close()
        helper = nil
    }

    /// Whisper sometimes "hears" stock phrases in near-silence. Drop a transcript that is only one of them.
    static let hallucinations: Set<String> = ["thank you", "thanks for watching", "thank you for watching", "you", "bye", "."]
    static func clean(_ t: String) -> String {
        let norm = t.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        return hallucinations.contains(norm) ? "" : t
    }
}

public enum STTError: Error, CustomStringConvertible, LocalizedError {
    case helperMissing(String)
    case helperExited
    case helper(String)
    public var description: String {
        switch self {
        case .helperMissing(let p): return "speech helper not found at \(p) (run `swift build`)"
        case .helperExited: return "speech helper exited"
        case .helper(let s): return "speech helper: \(s)"
        }
    }
    public var errorDescription: String? { description }
}

/// A running `zoe-stt`. Requests run one at a time on a private queue, each blocking until its final reply.
final class STTHelper: @unchecked Sendable {
    private let process: Process
    private let input: FileHandle
    private let reader: FDReader
    private let output: FileHandle   // kept open for `reader`
    private let queue = DispatchQueue(label: "zoe.stt.helper", qos: .userInitiated)
    var pid: Int32 { process.processIdentifier }
    var isRunning: Bool { process.isRunning }

    private init(process: Process, input: FileHandle, output: FileHandle) {
        self.process = process; self.input = input; self.output = output
        reader = FDReader(fd: output.fileDescriptor)
    }

    static func launch(executable: URL, modelsDirectory: URL) throws -> STTHelper {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw STTError.helperMissing(executable.path) }
        let p = Process()
        p.executableURL = executable
        p.arguments = ["--models", modelsDirectory.path]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.standardError   // the helper's log goes to the app's log
        _ = fcntl(inPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)   // a dead helper is an error, not a crash
        try p.run()
        return STTHelper(process: p, input: inPipe.fileHandleForWriting, output: outPipe.fileHandleForReading)
    }

    /// Sends one request frame and waits for its final reply; progress replies go to `progress`.
    func call(_ frame: Data, progress: (@Sendable (Double) -> Void)? = nil) async throws -> STTWire.Reply {
        try await withCheckedThrowingContinuation { c in
            queue.async { [self] in
                guard writeAll(input.fileDescriptor, frame) else { c.resume(throwing: STTError.helperExited); return }
                while let line = reader.readLine() {
                    guard let r = STTWire.decode(STTWire.Reply.self, line) else { continue }
                    if !r.isFinal { progress?(r.progress ?? 0); continue }
                    if r.event == "error" { c.resume(throwing: STTError.helper(r.error ?? "unknown error")) } else { c.resume(returning: r) }
                    return
                }
                c.resume(throwing: STTError.helperExited)
            }
        }
    }

    /// Closes the helper's stdin after any request in flight; it exits on end of input. Killed if it hasn't
    /// gone after 2 s.
    func close() {
        queue.async { [self] in
            try? input.close()
            let p = process
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if p.isRunning { p.terminate() } }
        }
    }
}
