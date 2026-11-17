@preconcurrency import AVFoundation

/// Converts any PCM buffer (e.g. the 48 kHz voice-processing input, or a 22 kHz file) to 16 kHz mono
/// Float32, the format VAD and Whisper use. Only the first channel is taken: the voice-processing input
/// has 9 identical channels (F03).
public final class Resampler: @unchecked Sendable {
    public static let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    public init() {}

    public func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let mono = firstChannel(buffer)
        if inputFormat != mono.format {
            inputFormat = mono.format
            converter = AVAudioConverter(from: mono.format, to: Self.target)
        }
        guard let converter else { return [] }
        let ratio = Self.target.sampleRate / mono.format.sampleRate
        let cap = AVAudioFrameCount(Double(mono.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.target, frameCapacity: cap) else { return [] }
        nonisolated(unsafe) var fed = false
        nonisolated(unsafe) let input = mono
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return input
        }
        guard err == nil, let p = out.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: p[0], count: Int(out.frameLength)))
    }

    /// A mono Float32 copy of channel 0 at the buffer's own rate.
    private func firstChannel(_ b: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: b.format.sampleRate, channels: 1, interleaved: false)!
        let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: b.frameLength)!
        out.frameLength = b.frameLength
        let n = Int(b.frameLength)
        let dst = out.floatChannelData![0]
        if let src = b.floatChannelData {
            dst.update(from: src[0], count: n)
        } else if let src = b.int16ChannelData {
            let stride = b.format.isInterleaved ? Int(b.format.channelCount) : 1
            for i in 0..<n { dst[i] = Float(src[0][i * stride]) / 32768 }
        }
        return out
    }

    /// Reads a whole audio file as 16 kHz mono Float32 (tests and tools).
    public static func load(_ url: URL) throws -> [Float] {
        let f = try AVAudioFile(forReading: url)
        let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
        try f.read(into: b)
        return Resampler().convert(b)
    }
}
