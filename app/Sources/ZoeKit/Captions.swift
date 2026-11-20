@preconcurrency import AVFoundation
import Speech

/// Live captions while I speak (#4/#6): Apple's on-device SpeechTranscriber, fed the same 16 kHz samples as
/// VAD. Only for the bubble — the transcript sent to Claude comes from Whisper (F04: SpeechTranscriber's
/// word errors are too high for that, but its partial results arrive in ~50 ms).
///
/// One session per turn: `begin()` when listening starts, `end()` when the turn ends. `feed` may be called
/// from any queue (it only converts and yields into the analyzer's input stream).
public final class LiveCaptions: @unchecked Sendable {
    /// The caption so far (finalised text + the current guess), on the main actor.
    public var onText: (@MainActor @Sendable (String) -> Void)?

    private let lock = NSLock()
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?
    private var format: AVAudioFormat?
    private var session: Task<Void, Never>?
    private var generation = 0
    private let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    public private(set) var available = true

    public init() {}

    public func begin() {
        end()
        lock.lock(); generation += 1; let gen = generation; lock.unlock()
        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        session = Task { [weak self] in await self?.run(stream: stream, continuation: cont, gen: gen) }
    }

    public func end() {
        lock.lock()
        continuation?.finish(); continuation = nil; converter = nil
        lock.unlock()
        session?.cancel(); session = nil
    }

    public func feed(_ samples: [Float]) {
        lock.lock(); defer { lock.unlock() }
        guard let cont = continuation, let conv = converter, let fmt = format, !samples.isEmpty,
              let inBuf = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        inBuf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { inBuf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let cap = AVAudioFrameCount(Double(samples.count) * fmt.sampleRate / 16000) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: cap) else { return }
        nonisolated(unsafe) var fed = false
        conv.convert(to: out, error: nil) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return inBuf
        }
        if out.frameLength > 0 { cont.yield(AnalyzerInput(buffer: out)) }
    }

    private func run(stream: AsyncStream<AnalyzerInput>, continuation cont: AsyncStream<AnalyzerInput>.Continuation, gen: Int) async {
        let locale = Locale(identifier: "en-US")
        let t = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
        do {
            if await AssetInventory.status(forModules: [t]) != .installed {
                if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) { try await req.downloadAndInstall() }
            }
            let analyzer = SpeechAnalyzer(modules: [t], options: .init(priority: .userInitiated, modelRetention: .processLifetime))
            guard let fmt = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t]),
                  let conv = AVAudioConverter(from: inputFormat, to: fmt) else { available = false; return }
            try await analyzer.prepareToAnalyze(in: fmt)
            let current = lock.withLock { () -> Bool in
                guard gen == generation else { return false }
                continuation = cont; converter = conv; format = fmt
                return true
            }
            guard current, !Task.isCancelled else { return }
            try await analyzer.start(inputSequence: stream)
            var final = ""
            for try await r in t.results {
                if Task.isCancelled { break }
                let s = String(r.text.characters)
                let text: String
                if r.isFinal { final += s; text = final } else { text = final + s }
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if let cb = onText, !trimmed.isEmpty { await MainActor.run { cb(trimmed) } }
            }
            await analyzer.cancelAndFinishNow()
        } catch {
            available = false
        }
    }
}
