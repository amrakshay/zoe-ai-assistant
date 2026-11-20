import Foundation
import OnnxRuntimeBindings

/// Silero VAD v5 on ONNX Runtime: 16 kHz mono, 512-sample windows (32 ms) with 64 samples of context,
/// recurrent state carried between windows (as in the official Python wrapper).
public final class SileroVAD: @unchecked Sendable {
    public static let window = 512
    static let context = 64

    private let env: ORTEnv
    private let session: ORTSession
    private var state = [Float](repeating: 0, count: 2 * 1 * 128)
    private var ctx = [Float](repeating: 0, count: SileroVAD.context)
    private let sr: ORTValue

    public init(modelPath: URL) throws {
        env = try ORTEnv(loggingLevel: .warning)
        let o = try ORTSessionOptions()
        try o.setIntraOpNumThreads(1)
        try o.setGraphOptimizationLevel(.all)
        session = try ORTSession(env: env, modelPath: modelPath.path, sessionOptions: o)
        var rate: Int64 = 16000
        sr = try ORTValue(tensorData: NSMutableData(bytes: &rate, length: 8), elementType: .int64, shape: [])
    }

    public func reset() {
        state = [Float](repeating: 0, count: state.count)
        ctx = [Float](repeating: 0, count: ctx.count)
    }

    /// Speech probability for one 512-sample window.
    public func probability(_ samples: ArraySlice<Float>) throws -> Float {
        precondition(samples.count == Self.window)
        let x = ctx + samples
        ctx = Array(x.suffix(Self.context))
        let input = try tensor(x, [1, x.count])
        let st = try tensor(state, [2, 1, 128])
        let out = try session.run(withInputs: ["input": input, "state": st, "sr": sr],
                                  outputNames: ["output", "stateN"], runOptions: nil)
        state = try floats(out["stateN"]!)
        return try floats(out["output"]!)[0]
    }

    private func tensor(_ f: [Float], _ shape: [Int]) throws -> ORTValue {
        let d = f.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress!, length: $0.count * 4) }
        return try ORTValue(tensorData: d, elementType: .float, shape: shape.map { NSNumber(value: $0) })
    }

    private func floats(_ v: ORTValue) throws -> [Float] {
        let d = try v.tensorData() as Data
        return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}

/// Turns per-window probabilities into speech start / end events, with hysteresis:
/// start after `minSpeech` above `onThreshold`; end after `minSilence` below `offThreshold`.
public struct SpeechSegmenter: Sendable {
    public enum Event: Sendable, Equatable { case start(TimeInterval), end(TimeInterval) }

    public var onThreshold: Float = 0.5
    public var offThreshold: Float = 0.35
    public var minSpeech: TimeInterval = 0.25
    public var minSilence: TimeInterval = 0.7     // PLAN.md §2.1: VAD's ~0.7 s end-of-turn window

    public private(set) var inSpeech = false
    private var candidate: TimeInterval?
    private var silenceSince: TimeInterval?

    public init() {}

    /// `t` is the time at the end of the window.
    public mutating func feed(probability p: Float, at t: TimeInterval) -> Event? {
        if !inSpeech {
            if p >= onThreshold {
                if candidate == nil { candidate = t - Double(SileroVAD.window) / 16000 }
                if t - candidate! >= minSpeech { inSpeech = true; silenceSince = nil; return .start(candidate!) }
            } else { candidate = nil }
            return nil
        }
        if p < offThreshold {
            if silenceSince == nil { silenceSince = t }
            if t - silenceSince! >= minSilence { inSpeech = false; candidate = nil; return .end(silenceSince!) }
        } else { silenceSince = nil }
        return nil
    }

    public mutating func reset() { inSpeech = false; candidate = nil; silenceSince = nil }
}
