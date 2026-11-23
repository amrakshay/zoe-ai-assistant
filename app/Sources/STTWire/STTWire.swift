import Darwin
import Foundation

/// The protocol between the app and `zoe-stt`, the helper process that runs Whisper (#41).
///
/// Requests go to the helper's stdin, replies come from its stdout, one JSON object per line:
///
///     app → helper   {"op":"load"}                          load Whisper (downloads it on first use)
///                    {"op":"transcribe","samples":N}        followed by exactly N × 4 bytes:
///                                                           16 kHz mono Float32, little-endian
///                    {"op":"stats"}                         the helper's own memory use
///     helper → app   {"event":"progress","progress":0.4}    download progress (zero or more, then one of:)
///                    {"event":"loaded","millis":1150}
///                    {"event":"text","text":"…","millis":480}
///                    {"event":"stats","footprintMB":210,"maxRSSMB":215}
///                    {"event":"error","error":"…"}
///
/// Every request gets exactly one final reply, in order. The helper exits when its stdin closes, which is
/// how the app unloads Whisper (and how the helper goes away if the app dies). It logs only to stderr.
///
/// Kept apart from ZoeKit on purpose: the helper depends only on this module and WhisperKit, so rebuilding
/// the app doesn't rebuild the helper, and Core ML's Neural Engine compile of Whisper stays valid.
#if !_endian(little)
#error("STTWire sends samples in native byte order, which must be little-endian")
#endif

public enum STTWire {
    /// Whisper large-v3 turbo (F04: no prompt).
    public static let variant = "large-v3-v20240930_turbo"
    public static let sampleRate = 16_000
    /// Refuse absurd frames: 10 minutes of audio.
    public static let maxSamples = sampleRate * 600

    public struct Request: Codable, Equatable, Sendable {
        public var op: String
        public var samples: Int?
        public init(op: String, samples: Int? = nil) { self.op = op; self.samples = samples }
    }

    public struct Reply: Codable, Equatable, Sendable {
        public var event: String
        public var progress: Double?
        public var text: String?
        public var millis: Double?
        public var footprintMB: Double?
        public var maxRSSMB: Double?
        public var error: String?
        public init(event: String, progress: Double? = nil, text: String? = nil, millis: Double? = nil,
                    footprintMB: Double? = nil, maxRSSMB: Double? = nil, error: String? = nil) {
            self.event = event; self.progress = progress; self.text = text; self.millis = millis
            self.footprintMB = footprintMB; self.maxRSSMB = maxRSSMB; self.error = error
        }
        public var isFinal: Bool { event != "progress" }
    }

    /// One JSON line. JSONEncoder escapes newlines inside strings, so the line has exactly one "\n".
    public static func line<T: Encodable>(_ value: T) -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var d = (try? enc.encode(value)) ?? Data("{}".utf8)
        d.append(0x0A)
        return d
    }

    public static func decode<T: Decodable>(_ type: T.Type, _ line: Data) -> T? {
        try? JSONDecoder().decode(type, from: line)
    }

    /// A transcribe request: the header line, then the samples as little-endian Float32.
    public static func transcribeFrame(_ samples: [Float]) -> Data {
        var d = line(Request(op: "transcribe", samples: samples.count))
        // Apple Silicon is little-endian, so the samples' memory is already the wire format.
        samples.withUnsafeBytes { d.append(contentsOf: $0) }
        return d
    }

    public static func samples(from bytes: Data) -> [Float] {
        let n = bytes.count / 4
        return [Float](unsafeUninitializedCapacity: n) { buf, count in
            if n > 0 { bytes.withUnsafeBytes { raw in _ = memcpy(buf.baseAddress!, raw.baseAddress!, n * 4) } }
            count = n
        }
    }
}

/// Blocking reads of lines and fixed-size frames from a file descriptor (a pipe).
public final class FDReader: @unchecked Sendable {
    public let fd: Int32
    private var buffer = Data()
    private var eof = false
    public init(fd: Int32) { self.fd = fd }

    private func fill() -> Bool {
        if eof { return false }
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if n > 0 { buffer.append(contentsOf: chunk[0..<n]); return true }
            if n < 0 && errno == EINTR { continue }
            eof = true
            return false
        }
    }

    /// The next line without its "\n", or nil at end of stream. Lines longer than `limit` are an error (nil).
    public func readLine(limit: Int = 1 << 20) -> Data? {
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[buffer.startIndex..<nl])
                buffer.removeSubrange(buffer.startIndex...nl)
                return line
            }
            if buffer.count > limit || !fill() { return nil }
        }
    }

    /// Exactly `count` bytes, or nil if the stream ends first.
    public func read(exactly count: Int) -> Data? {
        while buffer.count < count { if !fill() { return nil } }
        let out = Data(buffer.prefix(count))
        buffer.removeSubrange(buffer.startIndex..<buffer.startIndex + count)
        return out
    }
}

/// Writes all of `data` to `fd`. False if the other end is gone (callers set F_SETNOSIGPIPE, or ignore SIGPIPE).
@discardableResult
public func writeAll(_ fd: Int32, _ data: Data) -> Bool {
    data.withUnsafeBytes { raw -> Bool in
        var off = 0
        while off < raw.count {
            let n = Darwin.write(fd, raw.baseAddress! + off, raw.count - off)
            if n > 0 { off += n } else if n < 0 && errno == EINTR { continue } else { return false }
        }
        return true
    }
}
