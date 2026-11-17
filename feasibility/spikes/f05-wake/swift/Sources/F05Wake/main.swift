// F05 spike: openWakeWord mel -> embedding -> hey_claude head on ONNX Runtime, in Swift.
// Minimal port of openwakeword 0.6 AudioFeatures._streaming_features + Model.predict
// for 80 ms (1280-sample) frames. Spike code, not production.
import Darwin
import Foundation
import OnnxRuntimeBindings

let frameSamples = 1280
let melBins = 32
let embWindow = 76
let embDim = 96
let headFrames = 16

final class WakePipeline {
    let env: ORTEnv
    let mel: ORTSession
    let emb: ORTSession
    let head: ORTSession
    let headIn: String
    let headOut: String

    var raw: [Int16] = []                 // last <= 16000*10 samples
    var melBuf: [[Float]] = []            // frames x 32
    var feat: [[Float]] = []              // embeddings x 96
    var nPredictions = 0
    // Optional energy gate (spike experiment): skip mel/embedding/head while the last
    // `gateHold` frames were all below `gateRMS`. 0 disables.
    var gateRMS: Double = 0
    let gateHold = 16
    var quietFrames = 0
    var skipped = 0
    var tMel = 0.0, tEmb = 0.0, tHead = 0.0  // seconds, for profiling

    init(modelsDir: String, head headName: String, coreML: Bool) throws {
        env = try ORTEnv(loggingLevel: .warning)
        func opts() throws -> ORTSessionOptions {
            let o = try ORTSessionOptions()
            try o.setIntraOpNumThreads(1)
            try o.setGraphOptimizationLevel(.all)
            if CommandLine.arguments.contains("--xnnpack") {
                let x = ORTXnnpackExecutionProviderOptions()
                x.intra_op_num_threads = 1
                try o.appendXnnpackExecutionProvider(with: x)
            }
            if coreML {
                let c = ORTCoreMLExecutionProviderOptions()
                try o.appendCoreMLExecutionProvider(with: c)
            }
            return o
        }
        mel = try ORTSession(env: env, modelPath: "\(modelsDir)/melspectrogram.onnx", sessionOptions: opts())
        emb = try ORTSession(env: env, modelPath: "\(modelsDir)/embedding_model.onnx", sessionOptions: opts())
        head = try ORTSession(env: env, modelPath: "\(modelsDir)/\(headName).onnx", sessionOptions: opts())
        headIn = try head.inputNames()[0]
        headOut = try head.outputNames()[0]
        try reset()
    }

    func reset() throws {
        raw = []
        melBuf = Array(repeating: Array(repeating: 1, count: melBins), count: embWindow)
        nPredictions = 0
        // openwakeword seeds the feature buffer with embeddings of 4 s of random noise
        // (np.random.randint(-1000, 1000)); same distribution, different RNG.
        var g = SystemRandomNumberGenerator()
        let noise = (0..<(16000 * 4)).map { _ in Int16.random(in: -1000..<1000, using: &g) }
        let spec = try melspec(noise)
        var windows: [[[Float]]] = []
        var i = 0
        while i + embWindow <= spec.count { windows.append(Array(spec[i..<i + embWindow])); i += 8 }
        feat = try embed(windows)
    }

    private func tensor(_ floats: [Float], _ shape: [Int]) throws -> ORTValue {
        let d = floats.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress!, length: $0.count * 4) }
        return try ORTValue(tensorData: d, elementType: .float, shape: shape.map { NSNumber(value: $0) })
    }

    private func floats(_ v: ORTValue) throws -> [Float] {
        let d = try v.tensorData()
        let n = d.length / 4
        return Array(UnsafeBufferPointer(start: d.bytes.assumingMemoryBound(to: Float.self), count: n))
    }

    /// melspectrogram.onnx on int16 samples (as float), then x/10 + 2.
    func melspec(_ x: [Int16]) throws -> [[Float]] {
        let input = try tensor(x.map { Float($0) }, [1, x.count])
        let out = try mel.run(withInputs: ["input": input], outputNames: ["output"], runOptions: nil)
        let f = try floats(out["output"]!)
        let frames = f.count / melBins
        return (0..<frames).map { r in (0..<melBins).map { f[r * melBins + $0] / 10 + 2 } }
    }

    func embed(_ windows: [[[Float]]]) throws -> [[Float]] {
        var flat: [Float] = []
        flat.reserveCapacity(windows.count * embWindow * melBins)
        for w in windows { for row in w { flat.append(contentsOf: row) } }
        let input = try tensor(flat, [windows.count, embWindow, melBins, 1])
        let out = try emb.run(withInputs: ["input_1": input], outputNames: ["conv2d_19"], runOptions: nil)
        let f = try floats(out["conv2d_19"]!)
        return (0..<windows.count).map { Array(f[$0 * embDim..<($0 + 1) * embDim]) }
    }

    /// Feed n*80 ms at once (openwakeword's multi-chunk path): one mel call, one batched
    /// embedding call, one head call per 80 ms step. Returns the max score.
    func predictBatch(_ chunk: ArraySlice<Int16>) throws -> Float {
        let n = chunk.count / frameSamples
        precondition(n >= 1 && chunk.count == n * frameSamples)
        if n == 1 { return try predict(chunk) }
        raw.append(contentsOf: chunk)
        if raw.count > 160_000 { raw.removeFirst(raw.count - 160_000) }
        var t = CFAbsoluteTimeGetCurrent()
        melBuf.append(contentsOf: try melspec(Array(raw.suffix(min(raw.count, chunk.count + 480)))))
        if melBuf.count > 970 { melBuf.removeFirst(melBuf.count - 970) }
        tMel += CFAbsoluteTimeGetCurrent() - t
        t = CFAbsoluteTimeGetCurrent()
        var windows: [[[Float]]] = []
        for i in stride(from: n - 1, through: 0, by: -1) {
            let end = melBuf.count - 8 * i
            if end - embWindow >= 0 { windows.append(Array(melBuf[(end - embWindow)..<end])) }
        }
        feat.append(contentsOf: try embed(windows))
        if feat.count > 120 { feat.removeFirst(feat.count - 120) }
        tEmb += CFAbsoluteTimeGetCurrent() - t
        t = CFAbsoluteTimeGetCurrent()
        var best: Float = 0
        for i in stride(from: n - 1, through: 0, by: -1) {
            let end = feat.count - i
            let x = Array(feat[(end - headFrames)..<end].joined())
            let out = try head.run(withInputs: [headIn: try tensor(x, [1, headFrames, embDim])],
                                   outputNames: [headOut], runOptions: nil)
            best = max(best, try floats(out[headOut]!)[0])
        }
        tHead += CFAbsoluteTimeGetCurrent() - t
        nPredictions += 1
        return nPredictions <= 5 ? 0 : best
    }

    /// Feed exactly one 80 ms frame; returns the head score (openwakeword semantics).
    func predict(_ frame: ArraySlice<Int16>) throws -> Float {
        precondition(frame.count == frameSamples)
        raw.append(contentsOf: frame)
        if raw.count > 160_000 { raw.removeFirst(raw.count - 160_000) }
        if gateRMS > 0 {
            var e = 0.0
            for v in frame { e += Double(v) * Double(v) }
            quietFrames = (e / Double(frameSamples)).squareRoot() < gateRMS ? quietFrames + 1 : 0
            if quietFrames > gateHold {
                // keep buffers in step without inference: repeat the last quiet mel rows and embedding
                skipped += 1
                let lastMel = melBuf.last!
                for _ in 0..<8 { melBuf.append(lastMel) }
                if melBuf.count > 970 { melBuf.removeFirst(melBuf.count - 970) }
                feat.append(feat.last!)
                if feat.count > 120 { feat.removeFirst(feat.count - 120) }
                nPredictions += 1
                return 0
            }
        }
        if raw.count >= 400 {
            let take = min(raw.count, frameSamples + 160 * 3)
            let t = CFAbsoluteTimeGetCurrent()
            melBuf.append(contentsOf: try melspec(Array(raw.suffix(take))))
            tMel += CFAbsoluteTimeGetCurrent() - t
            if melBuf.count > 970 { melBuf.removeFirst(melBuf.count - 970) }
        }
        let w = Array(melBuf.suffix(embWindow))
        if w.count == embWindow {
            let t = CFAbsoluteTimeGetCurrent()
            feat.append(contentsOf: try embed([w]))
            tEmb += CFAbsoluteTimeGetCurrent() - t
            if feat.count > 120 { feat.removeFirst(feat.count - 120) }
        }
        let th = CFAbsoluteTimeGetCurrent()
        defer { tHead += CFAbsoluteTimeGetCurrent() - th }
        let x = Array(feat.suffix(headFrames).joined())
        let out = try head.run(withInputs: [headIn: try tensor(x, [1, headFrames, embDim])],
                               outputNames: [headOut], runOptions: nil)
        var score = try floats(out[headOut]!)[0]
        nPredictions += 1
        if nPredictions <= 5 { score = 0 }  // openwakeword zeroes the first 5 predictions
        return score
    }
}

func loadWav(_ path: String) -> [Int16] {
    // Minimal RIFF reader: find the "data" chunk; assumes 16 kHz mono int16 (as written by `say`).
    let d = try! Data(contentsOf: URL(fileURLWithPath: path))
    var i = 12
    while i + 8 <= d.count {
        let id = String(bytes: d[i..<i + 4], encoding: .ascii)!
        let size = Int(d[i + 4]) | Int(d[i + 5]) << 8 | Int(d[i + 6]) << 16 | Int(d[i + 7]) << 24
        if id == "data" {
            let body = d[(i + 8)..<min(d.count, i + 8 + size)]
            return body.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        }
        i += 8 + size + (size & 1)
    }
    fatalError("no data chunk in \(path)")
}

func scores(_ p: WakePipeline, _ audio: [Int16]) throws -> [Float] {
    var out: [Float] = []
    var i = 0
    while i + frameSamples <= audio.count {
        out.append(try p.predict(audio[i..<i + frameSamples])); i += frameSamples
    }
    return out
}

func rssBytes() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? info.resident_size : 0
}

func footprintBytes() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? info.phys_footprint : 0
}

func cpuSeconds() -> Double {
    var r = rusage()
    getrusage(RUSAGE_SELF, &r)
    return Double(r.ru_utime.tv_sec) + Double(r.ru_utime.tv_usec) / 1e6
        + Double(r.ru_stime.tv_sec) + Double(r.ru_stime.tv_usec) / 1e6
}

// MARK: - CLI
let args = CommandLine.arguments
func usage() -> Never {
    print("""
    usage:
      F05Wake score <modelsDir> <listFile> <out.json> [--coreml]
          listFile lines: <key>\\t<wavPath>\\t<pad 0|1>   (key "long_concat" lines are concatenated)
      F05Wake realtime <modelsDir> <wav> <seconds> [--coreml]
    """)
    exit(2)
}
guard args.count >= 2 else { usage() }
let coreML = args.contains("--coreml")
// --qos ui|utility|background : set this thread's QoS class (affects P-core vs E-core placement)
if let i = args.firstIndex(of: "--qos"), i + 1 < args.count {
    let q: qos_class_t = ["ui": QOS_CLASS_USER_INTERACTIVE, "utility": QOS_CLASS_UTILITY,
                          "background": QOS_CLASS_BACKGROUND][args[i + 1]] ?? QOS_CLASS_DEFAULT
    pthread_set_qos_class_self_np(q, 0)
}
let t0 = Date()

switch args[1] {
case "score":
    guard args.count >= 5 else { usage() }
    let p = try WakePipeline(modelsDir: args[2], head: "hey_claude", coreML: coreML)
    p.gateRMS = args.firstIndex(of: "--gate").map { Double(args[$0 + 1])! } ?? 0
    let lines = try String(contentsOfFile: args[3], encoding: .utf8).split(separator: "\n")
    var result: [String: [Float]] = [:]
    var longAudio: [Int16] = []
    let pad = [Int16](repeating: 0, count: 16000)
    for l in lines {
        let f = l.split(separator: "\t").map(String.init)
        if f[0] == "long_concat" { longAudio += loadWav(f[1]); continue }
        try p.reset()
        let a = f[2] == "1" ? pad + loadWav(f[1]) + pad : loadWav(f[1])
        result[f[0]] = try scores(p, a)
    }
    if !longAudio.isEmpty { try p.reset(); result["long_concat"] = try scores(p, longAudio) }
    let json = try JSONSerialization.data(withJSONObject: result.mapValues { $0.map { Double($0) } })
    try json.write(to: URL(fileURLWithPath: args[4]))
    print(String(format: "scored %d entries in %.1f s", result.count, Date().timeIntervalSince(t0)))

case "realtime":
    guard args.count >= 5, let secs = Double(args[4]) else { usage() }
    let rssStart = rssBytes()
    let p = try WakePipeline(modelsDir: args[2], head: "hey_claude", coreML: coreML)
    p.gateRMS = args.firstIndex(of: "--gate").map { Double(args[$0 + 1])! } ?? 0
    let audio = args[3] == "silence" ? (0..<160_000).map { _ in Int16.random(in: -20...20) } : loadWav(args[3])
    let rssLoaded = rssBytes()
    let batch = args.firstIndex(of: "--batch").map { Int(args[$0 + 1])! } ?? 1
    let nFrames = Int(secs / (0.08 * Double(batch)))
    let step = frameSamples * batch
    // warm up 1 s, then measure
    for k in 0..<12 { let s = (k * frameSamples) % (audio.count - frameSamples); _ = try p.predict(audio[s..<s + frameSamples]) }
    let cpu0 = cpuSeconds()
    let wall0 = DispatchTime.now().uptimeNanoseconds
    var maxScore: Float = 0
    var perFrame: [Double] = []
    var peakRSS: UInt64 = 0
    for k in 0..<nFrames {
        // real-time pacing: wait until this frame's deadline, as an 80 ms audio callback would
        let deadline = wall0 + UInt64(Double(k + 1) * 0.08 * Double(batch) * 1e9)
        let now = DispatchTime.now().uptimeNanoseconds
        if deadline > now { usleep(useconds_t((deadline - now) / 1000)) }
        let s = ((k + 12) * step) % (audio.count - step)
        let t = DispatchTime.now().uptimeNanoseconds
        maxScore = max(maxScore, try p.predictBatch(audio[s..<s + step]))
        perFrame.append(Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6)
        if k % 50 == 0 { peakRSS = max(peakRSS, rssBytes()) }
    }
    let wall = Double(DispatchTime.now().uptimeNanoseconds - wall0) / 1e9
    let cpu = cpuSeconds() - cpu0
    perFrame.sort()
    print(String(format: "batch=%d (%.0f ms per call) ", batch, 80.0 * Double(batch)), terminator: "")
    print(String(format: "provider=%@ calls=%d wall=%.1fs cpu=%.3fs avgCPU=%.2f%% of one core",
                 coreML ? "CoreML" : (CommandLine.arguments.contains("--xnnpack") ? "XNNPACK" : "CPU"), nFrames, wall, cpu, 100 * cpu / wall))
    print(String(format: "per-frame ms: median %.2f p95 %.2f max %.2f", perFrame[perFrame.count / 2],
                 perFrame[Int(Double(perFrame.count) * 0.95)], perFrame.last!))
    print(String(format: "RSS MB: start %.1f, after load %.1f, peak %.1f, end %.1f; phys_footprint end %.1f MB",
                 Double(rssStart) / 1e6, Double(rssLoaded) / 1e6, Double(peakRSS) / 1e6,
                 Double(rssBytes()) / 1e6, Double(footprintBytes()) / 1e6))
    print(String(format: "max score %.3f; gate=%.0f skipped %d frames", maxScore, p.gateRMS, p.skipped))
    print(String(format: "stage ms/frame (incl. warm-up): mel %.3f emb %.3f head %.3f", p.tMel * 1000 / Double(nFrames + 12),
                 p.tEmb * 1000 / Double(nFrames + 12), p.tHead * 1000 / Double(nFrames + 12)))
default:
    usage()
}
