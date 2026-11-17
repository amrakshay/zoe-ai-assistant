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
    /// Keep at most this much audio per turn (2 minutes) so a stuck turn can't grow without bound.
    public var maxTurnSamples = 16000 * 120

    public init(vad: SileroVAD) { self.vad = vad }

    /// Start a new turn. Time in events is seconds since this call.
    public func begin() {
        vad.reset(); segmenter.reset()
        pending.removeAll(); turn.removeAll(); samplesSeen = 0; capturing = true
    }

    /// The audio captured so far in this turn; clears it and keeps listening.
    public func takeTurn() -> [Float] {
        defer { turn.removeAll(keepingCapacity: true); segmenter.reset() }
        return turn
    }

    public func clear() { turn.removeAll(keepingCapacity: true); segmenter.reset() }
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
            if let e = segmenter.feed(probability: p, at: Double(samplesSeen) / 16000) { onSpeech?(e) }
        }
        pending.removeFirst(used)
    }
}
