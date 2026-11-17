// F03 echo-cancellation spike. Build: swiftc -O -swift-version 5 f03.swift -o f03
// Modes: perm | voices | synth | rec <secs> <out.wav> | echo <vp|novp|speak> <outprefix> | idle <secs>
import AVFoundation
import Foundation
import Darwin

setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "voices"
let phrase = "Hi, this is your desktop assistant checking how well the microphone ignores my own voice. If echo cancellation works, this sentence should almost vanish from the recording."
let maxPlay = 5.5  // seconds of speech played

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }
func spin(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func qname(_ q: AVSpeechSynthesisVoiceQuality) -> String {
    switch q { case .premium: return "premium"; case .enhanced: return "enhanced"; default: return "default" }
}
func bestVoice() -> AVSpeechSynthesisVoice {
    if let id = ProcessInfo.processInfo.environment["VOICE_ID"], let v = AVSpeechSynthesisVoice(identifier: id) { return v }
    let vs = AVSpeechSynthesisVoice.speechVoices().filter { ["en-US", "en-GB", "en-IN"].contains($0.language) }
    let ranked = vs.sorted { a, b in
        if a.quality.rawValue != b.quality.rawValue { return a.quality.rawValue > b.quality.rawValue }
        return (a.language == "en-US" ? 1 : 0) > (b.language == "en-US" ? 1 : 0)
    }
    return ranked.first ?? AVSpeechSynthesisVoice(language: "en-US")!
}
func fmtDesc(_ f: AVAudioFormat) -> String {
    let cf: String
    switch f.commonFormat { case .pcmFormatFloat32: cf = "Float32"; case .pcmFormatInt16: cf = "Int16"; case .pcmFormatInt32: cf = "Int32"; case .pcmFormatFloat64: cf = "Float64"; default: cf = "other" }
    return "\(cf) \(Int(f.sampleRate)) Hz ch=\(f.channelCount) interleaved=\(f.isInterleaved)"
}
func floats(_ b: AVAudioPCMBuffer) -> [Float] {
    let n = Int(b.frameLength)
    if let p = b.floatChannelData { return Array(UnsafeBufferPointer(start: p[0], count: n)) }
    if let p = b.int16ChannelData { return (0..<n).map { Float(p[0][$0 * (b.format.isInterleaved ? Int(b.format.channelCount) : 1)]) / 32768 } }
    if let p = b.int32ChannelData { return (0..<n).map { Float(p[0][$0]) / 2147483648 } }
    return []
}
func writeWav(_ path: String, _ s: [Float], _ sr: Double) {
    let f = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
    let b = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: AVAudioFrameCount(max(s.count, 1)))!
    b.frameLength = AVAudioFrameCount(s.count)
    s.withUnsafeBufferPointer { b.floatChannelData![0].update(from: $0.baseAddress!, count: s.count) }
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sr, AVNumberOfChannelsKey: 1,
                                   AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
    let file = try! AVAudioFile(forWriting: URL(fileURLWithPath: path), settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    try! file.write(from: b)
}
func rms(_ s: ArraySlice<Float>) -> Float { s.isEmpty ? 0 : sqrt(s.reduce(0) { $0 + $1 * $1 } / Float(s.count)) }

// Synthesise to buffers; returns (mono float samples, sample rate, first-buffer latency, total, format string)
let synth = AVSpeechSynthesizer()
func synthesize(_ text: String, _ voice: AVSpeechSynthesisVoice) -> ([Float], Double, Double, Double, String) {
    let u = AVSpeechUtterance(string: text); u.voice = voice
    var out: [Float] = []; var sr = 0.0; var first = -1.0; var total = -1.0; var fd = ""; var nbuf = 0
    let t0 = now()
    synth.write(u) { buf in
        guard let pcm = buf as? AVAudioPCMBuffer else { return }
        if pcm.frameLength == 0 { total = now() - t0; return }
        if first < 0 { first = now() - t0; sr = pcm.format.sampleRate; fd = fmtDesc(pcm.format) }
        nbuf += 1
        out += floats(pcm)
    }
    let dl = now() + 20
    while total < 0 && now() < dl { spin(0.005) }
    if total < 0 { total = now() - t0 }
    return (out, sr, first, total, fd + " buffers=\(nbuf)")
}

func micStatus() -> String {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: return "authorized"; case .denied: return "denied"; case .restricted: return "restricted"
    case .notDetermined: return "notDetermined"; @unknown default: return "unknown"
    }
}

switch mode {
case "perm":
    print("mic auth before:", micStatus())
    if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
        var done = false
        AVCaptureDevice.requestAccess(for: .audio) { ok in print("requestAccess ->", ok); done = true }
        let dl = now() + 60; while !done && now() < dl { spin(0.1) }
    }
    print("mic auth after:", micStatus())

case "voices":
    for v in AVSpeechSynthesisVoice.speechVoices().filter({ ["en-US", "en-GB", "en-IN"].contains($0.language) })
        .sorted(by: { ($0.language, -$0.quality.rawValue, $0.name) < ($1.language, -$1.quality.rawValue, $1.name) }) {
        print("\(v.language)\t\(qname(v.quality))\t\(v.name)\t\(v.identifier)")
    }
    print("BEST:", bestVoice().identifier, qname(bestVoice().quality))

case "synth":
    let v = bestVoice(); print("voice:", v.identifier, qname(v.quality))
    for i in 1...3 {
        let (s, sr, first, total, fd) = synthesize(phrase, v)
        print(String(format: "run %d: first_buffer=%.0f ms total=%.0f ms audio=%.2f s RTF=%.3f format=%@", i, first * 1000, total * 1000, Double(s.count) / sr, total / (Double(s.count) / sr), fd))
        if i == 1 { writeWav("ref_full.wav", s, sr) }
    }
    let short = synthesize("On it.", v)
    print(String(format: "short 'On it.': first_buffer=%.0f ms total=%.0f ms", short.2 * 1000, short.3 * 1000))

case "rec":  // raw (no VP) mic capture in a separate process, used as the acoustic-echo reference
    let secs = Double(args[2])!; let path = args[3]
    let e = AVAudioEngine(); let inp = e.inputNode; let f = inp.outputFormat(forBus: 0)
    var rec: [Float] = []; let lock = NSLock()
    inp.installTap(onBus: 0, bufferSize: 1024, format: f) { b, _ in let x = floats(b); lock.lock(); rec += x; lock.unlock() }
    try! e.start(); print("rec started", fmtDesc(f), "t=", now())
    spin(secs); e.stop()
    writeWav(path, rec, f.sampleRate)
    print("rec saved", path, rec.count, "peak", rec.map { abs($0) }.max() ?? 0)

case "echo":
    let sub = args[2]; let prefix = args[3]
    let v = bestVoice()
    var (ref, rsr, _, _, _) = synthesize(phrase, v)
    ref = Array(ref.prefix(Int(maxPlay * rsr)))
    writeWav("\(prefix)_ref.wav", ref, rsr)
    let e = AVAudioEngine(); let inp = e.inputNode
    let player = AVAudioPlayerNode(); e.attach(player)
    let pf = AVAudioFormat(standardFormatWithSampleRate: rsr, channels: 1)!
    if ProcessInfo.processInfo.environment["GRAPH_FIRST"] != nil { e.connect(player, to: e.mainMixerNode, format: pf); print("graph built before VP") }
    if sub != "novp" {
        do { try inp.setVoiceProcessingEnabled(true); print("VP enabled: in=\(inp.isVoiceProcessingEnabled) out=\(e.outputNode.isVoiceProcessingEnabled)") }
        catch { print("setVoiceProcessingEnabled FAILED:", error); exit(2) }
        if ProcessInfo.processInfo.environment["DUCK_MIN"] != nil {
            inp.voiceProcessingOtherAudioDuckingConfiguration = AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
        }
        print("ducking config:", inp.voiceProcessingOtherAudioDuckingConfiguration.enableAdvancedDucking, inp.voiceProcessingOtherAudioDuckingConfiguration.duckingLevel.rawValue)
    }
    let inFmt = inp.outputFormat(forBus: 0); print("mic format:", fmtDesc(inFmt))
    if ProcessInfo.processInfo.environment["GRAPH_FIRST"] == nil { e.connect(player, to: e.mainMixerNode, format: pf) }
    print("output format:", fmtDesc(e.outputNode.outputFormat(forBus: 0)))
    var mic: [Float] = []; let lock = NSLock()
    let nch = Int(inFmt.channelCount); var chE = [Double](repeating: 0, count: nch * 2); var phase = 0  // per-channel energy: silence / play
    inp.installTap(onBus: 0, bufferSize: 1024, format: inFmt) { b, _ in
        let x = floats(b); lock.lock(); mic += x
        if phase < 2, let p = b.floatChannelData { for c in 0..<nch { for i in 0..<Int(b.frameLength) { chE[c * 2 + phase] += Double(p[c][i] * p[c][i]) } } }
        lock.unlock() }
    // mouth level: tap on player output, RMS per 20 ms window
    var levels: [(Double, Float)] = []; var tapCalls: [Double] = []
    let win = Int(rsr * 0.02)
    player.installTap(onBus: 0, bufferSize: AVAudioFrameCount(win), format: pf) { b, _ in
        let t = now(); let x = floats(b); var i = 0
        lock.lock(); tapCalls.append(t)
        while i + win <= x.count { levels.append((t, rms(x[i..<(i + win)]))); i += win }
        lock.unlock()
    }
    do { try e.start() } catch { print("engine.start FAILED:", error); exit(3) }; print("engine started t=", now())
    spin(1.5)
    lock.lock(); let playStartIdx = mic.count; phase = 1; lock.unlock()
    let tPlay = now()
    if sub == "speak" {
        let u = AVSpeechUtterance(string: phrase); u.voice = v
        synth.speak(u); spin(maxPlay); synth.stopSpeaking(at: .immediate)
    } else {
        let b = AVAudioPCMBuffer(pcmFormat: pf, frameCapacity: AVAudioFrameCount(ref.count))!
        b.frameLength = AVAudioFrameCount(ref.count)
        ref.withUnsafeBufferPointer { b.floatChannelData![0].update(from: $0.baseAddress!, count: ref.count) }
        player.scheduleBuffer(b, completionHandler: nil); player.play()
        spin(maxPlay)
    }
    lock.lock(); let playEndIdx = mic.count; phase = 2; lock.unlock()
    print("per-channel energy dB (silence, play):", (0..<nch).map { c in String(format: "ch%d %.1f/%.1f", c, 10 * log10(chE[c * 2] + 1e-12), 10 * log10(chE[c * 2 + 1] + 1e-12)) }.joined(separator: "  "))
    spin(1.5)
    e.stop()
    writeWav("\(prefix)_mic.wav", mic, inFmt.sampleRate)
    let allZero = mic.allSatisfy { $0 == 0 }
    print("mic samples:", mic.count, "allZero:", allZero, "peak:", mic.map { abs($0) }.max() ?? 0)
    print("play window samples:", playStartIdx, playEndIdx, "tPlay=", tPlay)
    if sub != "speak" {
        let ivs = zip(tapCalls.dropFirst(), tapCalls).map { ($0 - $1) * 1000 }
        let active = levels.filter { $0.1 > 0.001 }
        print(String(format: "mouth tap: calls=%d median interval=%.1f ms, 20ms windows=%d (active %d), max level=%.3f",
                     tapCalls.count, ivs.sorted()[ivs.count / 2], levels.count, active.count, levels.map { $0.1 }.max() ?? 0))
    }
    let meta = "{\"case\":\"\(sub)\",\"mic_sr\":\(inFmt.sampleRate),\"ref_sr\":\(rsr),\"play_start\":\(playStartIdx),\"play_end\":\(playEndIdx)}"
    try! meta.write(toFile: "\(prefix)_meta.json", atomically: true, encoding: .utf8)

case "idle":
    let secs = Double(args[2])!
    let e = AVAudioEngine(); let inp = e.inputNode
    let player = AVAudioPlayerNode(); e.attach(player)
    e.connect(player, to: e.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1))  // graph before VP (see report)
    if ProcessInfo.processInfo.environment["NOVP"] == nil { try! inp.setVoiceProcessingEnabled(true) }
    var n = 0; inp.installTap(onBus: 0, bufferSize: 1024, format: inp.outputFormat(forBus: 0)) { b, _ in n += Int(b.frameLength) }
    try! e.start(); print("idle pid", getpid(), "started")
    var ru0 = rusage(); getrusage(RUSAGE_SELF, &ru0); let t0 = now()
    spin(secs)
    var ru1 = rusage(); getrusage(RUSAGE_SELF, &ru1); let t1 = now()
    func sec(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
    let cpu = (sec(ru1.ru_utime) + sec(ru1.ru_stime)) - (sec(ru0.ru_utime) + sec(ru0.ru_stime))
    print(String(format: "idle %.1f s: cpu=%.3f s (%.2f%% of one core), maxrss=%.1f MB, mic frames=%d", t1 - t0, cpu, 100 * cpu / (t1 - t0), Double(ru1.ru_maxrss) / 1048576, n))
    e.stop()

default: print("unknown mode")
}
