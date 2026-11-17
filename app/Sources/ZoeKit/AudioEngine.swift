@preconcurrency import AVFoundation

/// The one audio engine (PLAN.md §3): mic in, synthesised voice out, with Apple's voice processing
/// (echo cancellation) on. It runs only during a conversation; `stop()` releases the mic.
///
/// F03 lessons applied: connect the output graph **before** enabling voice processing (otherwise
/// error −10875), and take channel 0 of the 9-channel voice-processing input.
public final class AudioEngine: @unchecked Sendable {
    public private(set) var engine: AVAudioEngine?
    public private(set) var player: AVAudioPlayerNode?
    /// 16 kHz mono samples from the mic, delivered on `samplesQueue`.
    public var onSamples: (@Sendable ([Float]) -> Void)?
    public let samplesQueue = DispatchQueue(label: "zoe.audio.samples")
    public private(set) var lastStartMillis: Double = 0

    /// Format the player expects (AVSpeechSynthesizer buffers are Float32 22,050 Hz mono, F03).
    public static let voiceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 22050, channels: 1, interleaved: false)!

    public init() {}

    public var isRunning: Bool { engine?.isRunning ?? false }

    public func start(voiceProcessing: Bool = true) throws {
        if isRunning { return }
        let t0 = DispatchTime.now()
        let e = AVAudioEngine()
        let p = AVAudioPlayerNode()
        e.attach(p)
        e.connect(p, to: e.mainMixerNode, format: Self.voiceFormat)   // graph first …
        let input = e.inputNode
        if voiceProcessing { try input.setVoiceProcessingEnabled(true) }  // … then voice processing
        let fmt = input.outputFormat(forBus: 0)
        let resampler = Resampler()
        let q = samplesQueue
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
            let s = resampler.convert(buf)
            guard !s.isEmpty, let cb = self?.onSamples else { return }
            q.async { cb(s) }
        }
        e.prepare()
        try e.start()
        engine = e; player = p
        lastStartMillis = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6
    }

    public func stop() {
        guard let e = engine else { return }
        player?.stop()
        e.inputNode.removeTap(onBus: 0)
        e.stop()
        try? e.inputNode.setVoiceProcessingEnabled(false)
        e.reset()
        engine = nil; player = nil
    }
}
