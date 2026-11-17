import Foundation
@preconcurrency import WhisperKit

/// WhisperKit isn't Sendable; it's only ever used inside the `WhisperSTT` actor.
final class KitBox: @unchecked Sendable { let kit: WhisperKit; init(_ k: WhisperKit) { kit = k } }

/// Speech-to-text for the final transcript of each turn (#4): Whisper large-v3-turbo via WhisperKit,
/// **no prompt** (F04 addendum 3: a term prompt didn't improve intent, added ~0.4 s and could leak into
/// the output).
///
/// The model (~1.5 GB on disk, ~185 MB in memory) is loaded when a conversation starts — while I'm still
/// speaking — and unloaded a while after it ends, so it doesn't sit in memory when Zoe is idle.
public actor WhisperSTT {
    public static let variant = "large-v3-v20240930_turbo"
    public var downloadBase: URL { ModelStore.directory.appendingPathComponent("whisper") }

    private var kit: WhisperKit?
    private var loading: Task<KitBox, Error>?
    public private(set) var lastLoadMillis: Double = 0

    public init() {}

    public var isLoaded: Bool { kit != nil }

    /// Core ML compiles the model for the Neural Engine on the first load (measured: 113–157 s, 17 s CPU,
    /// 1.4 GB peak); later loads take about 1.1 s. The compiled result is cached per macOS build, and a
    /// rebuilt app binary compiled again (so an app update likely costs one more compile). A marker per
    /// model, macOS build and app binary records that the compile has happened, so it runs at launch.
    private var preparedMarker: URL {
        let os = ProcessInfo.processInfo.operatingSystemVersionString.filter { $0.isLetter || $0.isNumber }
        let exe = Bundle.main.executableURL.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
        let stamp = Int(exe?.timeIntervalSince1970 ?? 0)
        return downloadBase.appendingPathComponent(".prepared-\(Self.variant)-\(os)-\(stamp)")
    }
    public var isPrepared: Bool { FileManager.default.fileExists(atPath: preparedMarker.path) }

    /// Loads (downloading the model on first use). Safe to call repeatedly.
    public func load(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        _ = try await loadKit(progress: progress)
    }

    private func loadKit(progress: (@Sendable (Double) -> Void)? = nil) async throws -> WhisperKit {
        if let kit { return kit }
        if let loading { return try await loading.value.kit }
        let base = downloadBase
        let t = Task { () throws -> KitBox in
            let folder = base.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(Self.variant)")
            if !FileManager.default.fileExists(atPath: folder.appendingPathComponent("AudioEncoder.mlmodelc").path) {
                try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                _ = try await WhisperKit.download(variant: Self.variant, downloadBase: base) { p in
                    progress?(p.fractionCompleted)
                }
            }
            let cfg = WhisperKitConfig(model: Self.variant, downloadBase: base, modelFolder: folder.path,
                                       verbose: false, logLevel: .error, prewarm: false, load: true, download: false)
            return KitBox(try await WhisperKit(cfg))
        }
        loading = t
        do {
            let t0 = Date()
            let k = try await t.value.kit
            lastLoadMillis = Date().timeIntervalSince(t0) * 1000
            kit = k; loading = nil
            if !isPrepared { FileManager.default.createFile(atPath: preparedMarker.path, contents: nil) }
            return k
        } catch {
            loading = nil
            throw error
        }
    }

    public struct Result: Sendable {
        public let text: String
        public let millis: Double
    }

    /// Transcribes 16 kHz mono samples. Returns trimmed text ("" if nothing was said).
    public func transcribe(_ samples: [Float]) async throws -> Result {
        let k = try await loadKit()
        let t0 = Date()
        let opts = DecodingOptions(task: .transcribe, language: "en", temperature: 0, usePrefillPrompt: true,
                                   skipSpecialTokens: true, withoutTimestamps: true)
        let results = try await k.transcribe(audioArray: samples, decodeOptions: opts)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return Result(text: Self.clean(text), millis: Date().timeIntervalSince(t0) * 1000)
    }

    public func unload() async {
        await kit?.unloadModels()
        kit = nil
    }

    /// Whisper sometimes "hears" stock phrases in near-silence. Drop a transcript that is only one of them.
    static let hallucinations: Set<String> = ["thank you", "thanks for watching", "thank you for watching", "you", "bye", "."]
    static func clean(_ t: String) -> String {
        let norm = t.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        return hallucinations.contains(norm) ? "" : t
    }
}
