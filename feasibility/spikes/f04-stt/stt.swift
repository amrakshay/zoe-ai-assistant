// F04 spike: on-device STT benchmark (SpeechAnalyzer/SpeechTranscriber, DictationTranscriber, SFSpeechRecognizer).
// Build: ./build.sh   (swiftc, Command Line Tools only)
// Usage:
//   stt info [--download en-US,en-IN]
//   stt run --engine st|dt|sf --locale en-US [--context ctx.txt] [--pad 0.0] [--chunk-ms 100] manifest.tsv audioDir
// `run` prints one JSON object per file (JSON lines) to stdout.
import AVFoundation
import Foundation
import Speech

setvbuf(stdout, nil, _IONBF, 0)

func nowMs() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }
func err(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

final class Box: @unchecked Sendable {
    let lock = NSLock()
    var finalText = ""
    var volatileText = ""
    var firstPartial: Double?
    var lastFinal: Double?
    var lastAny: Double?
    func with<T>(_ f: (Box) -> T) -> T { lock.lock(); defer { lock.unlock() }; return f(self) }
}

struct Out: Codable {
    var id: String; var engine: String; var locale: String; var ctx: Bool
    var hyp: String; var audioSec: Double
    var firstPartialMs: Double?; var finalAfterLastChunkMs: Double?; var wallMs: Double
    var error: String?
}

// MARK: audio helpers

func loadBuffer(_ path: String, padSec: Double) throws -> AVAudioPCMBuffer {
    let f = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let fmt = f.processingFormat  // Float32 deinterleaved
    let pad = AVAudioFrameCount(padSec * fmt.sampleRate)
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(f.length) + pad)!
    try f.read(into: buf)
    let n = Int(buf.frameLength)
    for ch in 0..<Int(fmt.channelCount) {
        let p = buf.floatChannelData![ch]
        for i in 0..<Int(pad) { p[n + i] = 0 }
    }
    buf.frameLength += pad
    return buf
}

func split(_ buf: AVAudioPCMBuffer, ms: Double) -> [AVAudioPCMBuffer] {
    let per = AVAudioFrameCount(buf.format.sampleRate * ms / 1000)
    var out: [AVAudioPCMBuffer] = []
    var off: AVAudioFrameCount = 0
    while off < buf.frameLength {
        let n = min(per, buf.frameLength - off)
        let c = AVAudioPCMBuffer(pcmFormat: buf.format, frameCapacity: n)!
        for ch in 0..<Int(buf.format.channelCount) {
            memcpy(c.floatChannelData![ch], buf.floatChannelData![ch] + Int(off), Int(n) * 4)
        }
        c.frameLength = n
        out.append(c)
        off += n
    }
    return out
}

func convert(_ b: AVAudioPCMBuffer, to fmt: AVAudioFormat) -> AVAudioPCMBuffer {
    if b.format == fmt { return b }
    let conv = AVAudioConverter(from: b.format, to: fmt)!
    let cap = AVAudioFrameCount(Double(b.frameLength) * fmt.sampleRate / b.format.sampleRate) + 64
    let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: cap)!
    var given = false
    var e: NSError?
    conv.convert(to: out, error: &e) { _, status in
        if given { status.pointee = .endOfStream; return nil }
        given = true; status.pointee = .haveData; return b
    }
    if let e { err("convert error: \(e)") }
    return out
}

/// Feed chunks paced in real time. Returns the timestamp right after the last chunk was handed over.
func paced(_ chunks: [AVAudioPCMBuffer], chunkMs: Double, start: Double, _ feed: (AVAudioPCMBuffer) -> Void) async -> Double {
    for (i, c) in chunks.enumerated() {
        // chunk i becomes "available" from the mic once its audio has been captured: (i+1)*chunkMs after start
        let due = start + Double(i + 1) * chunkMs
        let wait = due - nowMs()
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1e6)) }
        feed(c)
    }
    return nowMs()
}

// MARK: SpeechAnalyzer engines

func runAnalyzer(engine: String, locale: Locale, ctx: [String]?, buf: AVAudioPCMBuffer, chunkMs: Double) async throws -> (String, Double?, Double?, Double) {
    let module: any SpeechModule
    let box = Box()
    let collector: Task<Void, Error>
    if engine == "st" {
        let t = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
        module = t
        collector = Task {
            for try await r in t.results {
                let ts = nowMs()
                let s = String(r.text.characters)
                box.with { b in
                    if b.firstPartial == nil, !s.trimmingCharacters(in: .whitespaces).isEmpty { b.firstPartial = ts }
                    b.lastAny = ts
                    if r.isFinal { b.finalText += s; b.lastFinal = ts; b.volatileText = "" } else { b.volatileText = s }
                }
            }
        }
    } else {
        let t = DictationTranscriber(locale: locale, contentHints: [.shortForm], transcriptionOptions: [.punctuation], reportingOptions: [.volatileResults, .frequentFinalization], attributeOptions: [])
        module = t
        collector = Task {
            for try await r in t.results {
                let ts = nowMs()
                let s = String(r.text.characters)
                box.with { b in
                    if b.firstPartial == nil, !s.trimmingCharacters(in: .whitespaces).isEmpty { b.firstPartial = ts }
                    b.lastAny = ts
                    if r.isFinal { b.finalText += s; b.lastFinal = ts; b.volatileText = "" } else { b.volatileText = s }
                }
            }
        }
    }
    let analyzer = SpeechAnalyzer(modules: [module], options: .init(priority: .userInitiated, modelRetention: .processLifetime))
    guard let fmt = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else { throw NSError(domain: "stt", code: 1, userInfo: [NSLocalizedDescriptionKey: "no audio format"]) }
    try await analyzer.prepareToAnalyze(in: fmt)
    if let ctx {
        let c = AnalysisContext()
        c.contextualStrings[.general] = ctx
        try await analyzer.setContext(c)
    }
    let chunks = split(buf, ms: chunkMs).map { convert($0, to: fmt) }
    let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
    try await analyzer.start(inputSequence: stream)
    let t0 = nowMs()
    let tLast = await paced(chunks, chunkMs: chunkMs, start: t0) { cont.yield(AnalyzerInput(buffer: $0)) }
    cont.finish()
    try await analyzer.finalizeAndFinishThroughEndOfInput()
    try await collector.value
    let tEnd = nowMs()
    return box.with { b in
        let text = b.finalText.isEmpty ? b.volatileText : b.finalText
        let fin = (b.lastFinal ?? tEnd) - tLast
        return (text, b.firstPartial.map { $0 - t0 }, fin, tEnd - t0)
    }
}

// MARK: SFSpeechRecognizer engine

func runSF(locale: Locale, ctx: [String]?, buf: AVAudioPCMBuffer, chunkMs: Double) async throws -> (String, Double?, Double?, Double) {
    guard let rec = SFSpeechRecognizer(locale: locale) else { throw NSError(domain: "stt", code: 2, userInfo: [NSLocalizedDescriptionKey: "SFSpeechRecognizer nil for \(locale.identifier)"]) }
    guard rec.supportsOnDeviceRecognition else { throw NSError(domain: "stt", code: 3, userInfo: [NSLocalizedDescriptionKey: "no on-device support for \(locale.identifier)"]) }
    rec.queue = OperationQueue()
    let req = SFSpeechAudioBufferRecognitionRequest()
    req.requiresOnDeviceRecognition = true
    req.shouldReportPartialResults = true
    req.addsPunctuation = false
    if let ctx { req.contextualStrings = ctx }
    let box = Box()
    let chunks = split(buf, ms: chunkMs)
    var tLast = 0.0
    let t0 = nowMs()
    let done: Void = await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
        let once = Box()
        var resumed = false
        let finish = { once.with { _ in if !resumed { resumed = true; k.resume() } } }
        _ = rec.recognitionTask(with: req) { result, error in
            let ts = nowMs()
            if let result {
                let s = result.bestTranscription.formattedString
                box.with { b in
                    if b.firstPartial == nil, !s.isEmpty { b.firstPartial = ts }
                    b.lastAny = ts
                    b.volatileText = s
                    if result.isFinal { b.finalText = s; b.lastFinal = ts }
                }
                if result.isFinal { finish() }
            }
            if let error { err("SF error: \(error)"); finish() }
        }
        Task {
            tLast = await paced(chunks, chunkMs: chunkMs, start: t0) { req.append($0) }
            req.endAudio()
        }
    }
    _ = done
    let tEnd = nowMs()
    return box.with { b in
        let text = b.finalText.isEmpty ? b.volatileText : b.finalText
        return (text, b.firstPartial.map { $0 - t0 }, (b.lastFinal ?? tEnd) - tLast, tEnd - t0)
    }
}

// MARK: commands

func info(download: [String]) async {
    print("SpeechTranscriber.isAvailable = \(SpeechTranscriber.isAvailable)")
    let st = await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }.sorted()
    let sti = await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }.sorted()
    let dt = await DictationTranscriber.supportedLocales.map { $0.identifier(.bcp47) }.sorted()
    let dti = await DictationTranscriber.installedLocales.map { $0.identifier(.bcp47) }.sorted()
    print("SpeechTranscriber.supportedLocales (\(st.count)): \(st.joined(separator: " "))")
    print("SpeechTranscriber.installedLocales: \(sti.joined(separator: " "))")
    print("DictationTranscriber.supportedLocales (\(dt.count)): \(dt.joined(separator: " "))")
    print("DictationTranscriber.installedLocales: \(dti.joined(separator: " "))")
    for id in ["en-US", "en-IN", "en-GB", "hi-IN"] {
        let l = Locale(identifier: id)
        let eqS = await SpeechTranscriber.supportedLocale(equivalentTo: l)?.identifier(.bcp47) ?? "nil"
        let eqD = await DictationTranscriber.supportedLocale(equivalentTo: l)?.identifier(.bcp47) ?? "nil"
        let sMod = SpeechTranscriber(locale: l, preset: .progressiveTranscription)
        let dMod = DictationTranscriber(locale: l, preset: .progressiveShortDictation)
        let sS = await AssetInventory.status(forModules: [sMod])
        let dS = await AssetInventory.status(forModules: [dMod])
        let sfr = SFSpeechRecognizer(locale: l)
        print("\(id): ST equiv=\(eqS) status=\(sS) | DT equiv=\(eqD) status=\(dS) | SF available=\(sfr?.isAvailable ?? false) onDevice=\(sfr?.supportsOnDeviceRecognition ?? false)")
        if let f = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [sMod]) { print("  ST best format: \(f)") }
    }
    print("AssetInventory.maximumReservedLocales = \(AssetInventory.maximumReservedLocales)")
    print("AssetInventory.reservedLocales = \(await AssetInventory.reservedLocales.map { $0.identifier(.bcp47) })")
    print("SFSpeechRecognizer.authorizationStatus = \(SFSpeechRecognizer.authorizationStatus().rawValue) (0=notDetermined 1=denied 2=restricted 3=authorized)")
    for id in download {
        let l = Locale(identifier: id)
        for (name, m) in [("ST", SpeechTranscriber(locale: l, preset: .progressiveTranscription) as any SpeechModule),
                          ("DT", DictationTranscriber(locale: l, preset: .progressiveShortDictation) as any SpeechModule)] {
            do {
                let t0 = nowMs()
                if let req = try await AssetInventory.assetInstallationRequest(supporting: [m]) {
                    print("\(name) \(id): downloading... (progress total=\(req.progress.totalUnitCount))")
                    try await req.downloadAndInstall()
                    print("\(name) \(id): installed in \(Int(nowMs() - t0)) ms")
                } else {
                    print("\(name) \(id): no installation needed (already installed)")
                }
                print("\(name) \(id): status now \(await AssetInventory.status(forModules: [m]))")
            } catch {
                print("\(name) \(id): download FAILED: \(error)")
            }
        }
    }
}

func requestSFAuth() async -> SFSpeechRecognizerAuthorizationStatus {
    await withCheckedContinuation { k in SFSpeechRecognizer.requestAuthorization { k.resume(returning: $0) } }
}

func run(args: [String]) async {
    var engine = "st", localeId = "en-US", ctxPath: String?, pad = 0.0, chunkMs = 100.0
    var pos: [String] = []
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--engine": engine = args[i + 1]; i += 2
        case "--locale": localeId = args[i + 1]; i += 2
        case "--context": ctxPath = args[i + 1]; i += 2
        case "--pad": pad = Double(args[i + 1])!; i += 2
        case "--chunk-ms": chunkMs = Double(args[i + 1])!; i += 2
        default: pos.append(args[i]); i += 1
        }
    }
    let manifest = pos[0], dir = pos[1]
    let ctx: [String]? = ctxPath.map { try! String(contentsOfFile: $0, encoding: .utf8).split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    let locale = Locale(identifier: localeId)
    if engine == "sf" {
        let s = await requestSFAuth()
        err("SF authorization status: \(s.rawValue)")
        if s != .authorized { print("{\"error\":\"SFSpeechRecognizer not authorized (status \(s.rawValue))\"}"); return }
    }
    let lines = try! String(contentsOfFile: manifest, encoding: .utf8).split(separator: "\n")
    let enc = JSONEncoder()
    for line in lines {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        let id = parts[0]
        let path = "\(dir)/\(id).wav"
        var o = Out(id: id, engine: engine, locale: localeId, ctx: ctx != nil, hyp: "", audioSec: 0, wallMs: 0)
        do {
            let buf = try loadBuffer(path, padSec: pad)
            o.audioSec = Double(buf.frameLength) / buf.format.sampleRate
            let r = engine == "sf" ? try await runSF(locale: locale, ctx: ctx, buf: buf, chunkMs: chunkMs)
                                   : try await runAnalyzer(engine: engine, locale: locale, ctx: ctx, buf: buf, chunkMs: chunkMs)
            (o.hyp, o.firstPartialMs, o.finalAfterLastChunkMs, o.wallMs) = r
        } catch {
            o.error = "\(error)"
        }
        print(String(data: try! enc.encode(o), encoding: .utf8)!)
    }
}

let argv = Array(CommandLine.arguments.dropFirst())
let sema = DispatchSemaphore(value: 0)
Task {
    switch argv.first {
    case "info":
        var dl: [String] = []
        if let k = argv.firstIndex(of: "--download"), k + 1 < argv.count { dl = argv[k + 1].split(separator: ",").map(String.init) }
        await info(download: dl)
    case "run": await run(args: Array(argv.dropFirst()))
    default: err("usage: stt info [--download en-US,en-IN] | stt run --engine st|dt|sf --locale en-US [--context f] manifest dir")
    }
    sema.signal()
}
// keep main thread's run loop alive for framework callbacks
while sema.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
