@preconcurrency import AVFoundation

/// Speaks Zoe's replies (#5): `AVSpeechSynthesizer.write(toBufferCallback:)` in the Zoe (Premium) voice,
/// played through an `AVAudioPlayerNode`.
///
/// - Sentences are queued as they stream from the core and synthesised one at a time; each buffer is
///   scheduled as soon as it arrives, so the first sentence plays while later ones are still being written.
/// - Phase 1 is half-duplex (the listener is paused while Zoe speaks), so speech plays on its own small
///   output-only engine, started on demand and stopped a few seconds after the last word. With barge-in
///   (phase 8) it moves onto the voice-processing engine for echo cancellation (F03).
/// - `warmUp()` synthesises the cached acknowledgement at launch: the first Zoe buffer takes ~1.1 s cold,
///   ~50 ms warm (F03).
@MainActor
public final class Speaker {
    public let voice: AVSpeechSynthesisVoice
    /// Called once all queued speech of a reply has played (or right after `stop()`).
    public var onReplyDone: (() -> Void)?
    /// Output level (RMS, 0…1) while speech plays, about every 20–100 ms, on the main actor.
    public var onLevel: ((Float) -> Void)?
    /// Milliseconds from a reply's first `enqueue` to its first scheduled buffer; and engine start.
    public private(set) var lastFirstAudioMillis: Double = 0
    public private(set) var lastEngineStartMillis: Double = 0
    /// Stop the output engine this long after speech ends.
    public var idleStop: Duration = .seconds(5)

    private let synth = AVSpeechSynthesizer()
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var format: AVAudioFormat?
    private var queue: [String] = []
    private var synthesizing = false
    private var pendingBuffers = 0
    private var replyOpen = false          // more sentences may come
    private var replyActive = false
    private var generation = 0             // bumps on stop(); stale callbacks are ignored
    private var firstEnqueueAt: TimeInterval?
    private var idleTask: Task<Void, Never>?
    private var ack: [AVAudioPCMBuffer] = []

    public init(voice: AVSpeechSynthesisVoice? = nil) {
        self.voice = voice ?? Self.zoeVoice()
    }

    /// The Zoe Premium voice if installed, else the best-quality US English voice.
    public static func zoeVoice() -> AVSpeechSynthesisVoice {
        if let id = ProcessInfo.processInfo.environment["ZOE_VOICE_ID"], let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        let en = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        let ranked = en.sorted { a, b in
            let ka = (a.name == "Zoe" ? 2 : 0) + (a.language == "en-US" ? 1 : 0)
            let kb = (b.name == "Zoe" ? 2 : 0) + (b.language == "en-US" ? 1 : 0)
            return a.quality.rawValue != b.quality.rawValue ? a.quality.rawValue > b.quality.rawValue : ka > kb
        }
        return ranked.first ?? AVSpeechSynthesisVoice(language: "en-US")!
    }

    public var isSpeaking: Bool { replyActive }

    static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: - API

    /// Synthesises the acknowledgement into memory (this also warms the synthesiser up).
    public func warmUp(ack text: String = "On it.") async -> Double {
        let t0 = Self.now()
        ack = await synthesize(text)
        return (Self.now() - t0) * 1000
    }

    /// Plays the cached acknowledgement now (no synthesis). Part of the current reply.
    public func playAcknowledgement() {
        guard !ack.isEmpty else { return }
        beginReplyIfNeeded()
        for b in ack { schedule(b, gen: generation) }
    }

    /// Queues a sentence of the current reply.
    public func enqueue(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        beginReplyIfNeeded()
        if firstEnqueueAt == nil { firstEnqueueAt = Self.now() }
        queue.append(t)
        pump()
    }

    /// No more sentences for this reply; `onReplyDone` fires once everything has played.
    public func endReply() {
        guard replyActive else { onReplyDone?(); return }
        replyOpen = false
        checkDone()
    }

    /// Stops speaking at once and drops anything queued. Does not call `onReplyDone`.
    public func stop() {
        generation += 1
        queue.removeAll()
        if synthesizing { synth.stopSpeaking(at: .immediate) }
        synthesizing = false
        player?.stop()
        pendingBuffers = 0
        replyOpen = false; replyActive = false; firstEnqueueAt = nil
        scheduleIdleStop()
    }

    // MARK: - internals

    private func beginReplyIfNeeded() {
        idleTask?.cancel()
        if !replyActive { replyActive = true; replyOpen = true; firstEnqueueAt = nil }
    }

    private func pump() {
        guard !synthesizing, !queue.isEmpty else { return }
        synthesizing = true
        let text = queue.removeFirst()
        let gen = generation
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        synth.write(u) { [weak self] buf in
            guard let pcm = buf as? AVAudioPCMBuffer else { return }
            let copy = pcm.frameLength == 0 ? nil : Self.copy(pcm)
            MainActor.assumeIsolatedOrHop { [weak self] in
                guard let self, gen == self.generation else { return }
                if let copy { self.schedule(copy, gen: gen) } else {
                    self.synthesizing = false
                    self.pump()
                    self.checkDone()
                }
            }
        }
    }

    private func schedule(_ b: AVAudioPCMBuffer, gen: Int) {
        guard let p = ensureEngine(format: b.format) else { return }
        if let f = firstEnqueueAt {
            lastFirstAudioMillis = (Self.now() - f) * 1000
            firstEnqueueAt = nil
        }
        pendingBuffers += 1
        p.scheduleBuffer(b, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            MainActor.assumeIsolatedOrHop { [weak self] in
                guard let self, gen == self.generation else { return }
                self.pendingBuffers -= 1
                self.checkDone()
            }
        }
        if !p.isPlaying { p.play() }
    }

    private func checkDone() {
        guard replyActive, !replyOpen, !synthesizing, queue.isEmpty, pendingBuffers == 0 else { return }
        replyActive = false
        scheduleIdleStop()
        onReplyDone?()
    }

    private func ensureEngine(format f: AVAudioFormat) -> AVAudioPlayerNode? {
        if let e = engine, let p = player, e.isRunning, format == f { return p }
        stopEngine()
        let t0 = Self.now()
        let e = AVAudioEngine(), p = AVAudioPlayerNode()
        e.attach(p)
        e.connect(p, to: e.mainMixerNode, format: f)
        e.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil, block: Self.levelTap { [weak self] rms in self?.onLevel?(rms) })
        e.prepare()
        do { try e.start() } catch { return nil }
        lastEngineStartMillis = (Self.now() - t0) * 1000
        engine = e; player = p; format = f
        return p
    }

    private func scheduleIdleStop() {
        idleTask?.cancel()
        idleTask = Task { [weak self, idleStop] in
            try? await Task.sleep(for: idleStop)
            guard !Task.isCancelled, let self, !self.replyActive else { return }
            self.stopEngine()
        }
    }

    private func stopEngine() {
        engine?.mainMixerNode.removeTap(onBus: 0)
        player?.stop(); engine?.stop()
        engine = nil; player = nil; format = nil
    }

    private struct Buffers: @unchecked Sendable { var list: [AVAudioPCMBuffer] = [] }

    private func synthesize(_ text: String) async -> [AVAudioPCMBuffer] {
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        let r = await withCheckedContinuation { (c: CheckedContinuation<Buffers, Never>) in
            nonisolated(unsafe) var out = Buffers()
            nonisolated(unsafe) var resumed = false
            synth.write(u) { buf in
                guard let pcm = buf as? AVAudioPCMBuffer, !resumed else { return }
                if pcm.frameLength == 0 { resumed = true; c.resume(returning: out) } else { out.list.append(Self.copy(pcm)) }
            }
        }
        return r.list
    }

    /// The tap runs on an audio queue, so its closure must not be main-actor isolated (Swift 6 traps).
    nonisolated static func levelTap(_ report: @escaping @MainActor @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        { buf, _ in
            guard let d = buf.floatChannelData else { return }
            let n = Int(buf.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += d[0][i] * d[0][i] }
            let rms = n > 0 ? (sum / Float(n)).squareRoot() : 0
            DispatchQueue.main.async { report(rms) }
        }
    }

    nonisolated static func copy(_ b: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let c = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: b.frameLength)!
        c.frameLength = b.frameLength
        let n = Int(b.frameLength), ch = Int(b.format.channelCount)
        if let s = b.floatChannelData, let d = c.floatChannelData {
            for i in 0..<ch { d[i].update(from: s[i], count: n) }
        } else if let s = b.int16ChannelData, let d = c.int16ChannelData {
            for i in 0..<ch { d[i].update(from: s[i], count: n) }
        } else if let s = b.int32ChannelData, let d = c.int32ChannelData {
            for i in 0..<ch { d[i].update(from: s[i], count: n) }
        }
        return c
    }
}

extension MainActor {
    /// Runs `body` on the main actor: inline if already on the main thread, else hops there.
    static func assumeIsolatedOrHop(_ body: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread { MainActor.assumeIsolated(body) } else { DispatchQueue.main.async(execute: body) }
    }
}
