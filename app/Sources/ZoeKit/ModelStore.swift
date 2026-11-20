import CryptoKit
import Foundation

/// Downloaded models live in ~/Library/Application Support/Zoe/models, never in the repo. Each has a
/// pinned SHA-256; a file that doesn't match is deleted and never used.
public struct ModelFile: Sendable {
    public let name: String
    public let url: URL
    public let sha256: String

    /// Silero VAD v5 (MIT, snakers4/silero-vad), 16 kHz.
    public static let sileroVAD = ModelFile(
        name: "silero_vad.onnx",
        url: URL(string: "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx")!,
        sha256: "1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3")
}

public enum ModelStore {
    public static var directory: URL {
        if let d = ProcessInfo.processInfo.environment["ZOE_MODELS_DIR"] { return URL(fileURLWithPath: d) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Zoe/models")
    }

    public enum Failure: Error, CustomStringConvertible {
        case download(String), checksum(expected: String, got: String)
        public var description: String {
            switch self {
            case .download(let s): return "model download failed: \(s)"
            case .checksum(let e, let g): return "model checksum mismatch (expected \(e.prefix(12))…, got \(g.prefix(12))…)"
            }
        }
    }

    static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Path to a verified local copy, downloading it first if needed.
    public static func path(for m: ModelFile) async throws -> URL {
        let dest = directory.appendingPathComponent(m.name)
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            if (try? sha256(of: dest)) == m.sha256 { return dest }
            try? fm.removeItem(at: dest)
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let (tmp, response) = try await URLSession.shared.download(from: m.url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure.download("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        let got = try sha256(of: tmp)
        guard got == m.sha256 else { try? fm.removeItem(at: tmp); throw Failure.checksum(expected: m.sha256, got: got) }
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: tmp, to: dest)
        return dest
    }
}
