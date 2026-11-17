import Foundation

/// Collects the 16 kHz samples of the current turn and runs VAD over them, reporting speech start/end.
/// Call from one queue only (the audio engine's `samplesQueue`).
public final class Listener: @unchecked Sendable {
    public var onSpeech: (@Sendable (SpeechSegmenter.Event) -> Void)?

    private let vad: SileroVAD
    private var segmenter = SpeechSegmenter()
    private var pending: [Float] = []
    private var turn: [Float] = []
    private var samplesSeen = 0
    private var capturing = false
    private var turnBase = 0            // samplesSeen when this turn's buffer started
    private var speechStartInTurn: Int?
    /// Audio kept before the detected speech start.
    public var preRoll = 4800            // 0.3 s
    /// Keep at most this much audio per turn (2 minutes) so a stuck turn can't grow without bound.
    public var maxTurnSamples = 16000 * 120

    public init(vad: SileroVAD) { self.vad = vad }

    /// Start a new turn. Time in events is seconds since this call.
    public func begin() {
        vad.reset(); segmenter.reset()
        pending.removeAll(); turn.removeAll(); samplesSeen = 0; capturing = true
        turnBase = 0; speechStartInTurn = nil
    }

    /// The audio captured so far in this turn; clears it and keeps listening.
    /// The turn starts 0.3 s before the detected speech, if VAD saw speech; less silence means fewer
    /// Whisper hallucinations.
    public func takeTurn() -> [Float] {
        let from = min(turn.count, max(0, (speechStartInTurn ?? 0) - preRoll))
        defer { resetTurn() }
        return Array(turn[from...])
    }

    public func clear() { resetTurn() }

    private func resetTurn() {
        turn.removeAll(keepingCapacity: true); segmenter.reset()
        turnBase = samplesSeen + pending.count; speechStartInTurn = nil
    }
    public func pause() { capturing = false }
    public func resume() { if !capturing { begin() } }

    public func feed(_ samples: [Float]) {
        guard capturing else { return }
        if turn.count < maxTurnSamples { turn.append(contentsOf: samples.prefix(maxTurnSamples - turn.count)) }
        pending.append(contentsOf: samples)
        var used = 0
        while pending.count - used >= SileroVAD.window {
            let w = pending[used..<(used + SileroVAD.window)]
            used += SileroVAD.window
            samplesSeen += SileroVAD.window
            guard let p = try? vad.probability(w) else { continue }
            if let e = segmenter.feed(probability: p, at: Double(samplesSeen) / 16000) {
                if case .start(let t) = e, speechStartInTurn == nil { speechStartInTurn = max(0, Int(t * 16000) - turnBase) }
                onSpeech?(e)
            }
        }
        pending.removeFirst(used)
    }
}
