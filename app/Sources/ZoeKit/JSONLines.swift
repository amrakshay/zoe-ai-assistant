import Foundation

/// A message on the app <-> core link: a JSON object with a string `type` (PLAN.md §3).
public struct CoreMessage: @unchecked Sendable, Equatable {
    public let type: String
    public let fields: [String: Any]

    public init(_ type: String, _ fields: [String: Any] = [:]) {
        self.type = type
        var f = fields
        f["type"] = type
        self.fields = f
    }

    public subscript(key: String) -> Any? { fields[key] }
    public func string(_ key: String) -> String? { fields[key] as? String }

    /// One line of JSON ending in "\n". JSON escapes newlines inside strings, so a message is always one line.
    public func encoded() throws -> Data {
        var d = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])
        d.append(0x0A)
        return d
    }

    public static func == (a: CoreMessage, b: CoreMessage) -> Bool {
        NSDictionary(dictionary: a.fields).isEqual(to: b.fields)
    }
}

public enum LineError: Error, Equatable {
    case notJSONObject(String)
    case missingType
    case tooLong(Int)
}

/// Splits a byte stream into JSON-lines messages. Feed it whatever chunks the pipe delivers; it keeps
/// partial lines until their newline arrives. Bad lines become `.failure` and never stop the stream.
public struct JSONLineFramer {
    public static let maxLine = 1 << 20  // 1 MiB, same limit as the core
    private var buffer = Data()
    private var discarding = false  // inside an over-long line: drop bytes until its newline

    public init() {}

    public mutating func feed(_ chunk: Data) -> [Result<CoreMessage, LineError>] {
        buffer.append(chunk)
        var out: [Result<CoreMessage, LineError>] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            if discarding { discarding = false; continue }
            if let r = Self.parse(Data(line)) { out.append(r) }
        }
        if buffer.count > Self.maxLine {
            out.append(.failure(.tooLong(buffer.count)))
            buffer.removeAll(keepingCapacity: false)
            discarding = true
        }
        return out
    }

    /// nil for blank lines (ignored).
    static func parse(_ line: Data) -> Result<CoreMessage, LineError>? {
        let trimmed = line.drop { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }
        if trimmed.allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }) { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: line), let dict = obj as? [String: Any] else {
            return .failure(.notJSONObject(String(decoding: line.prefix(80), as: UTF8.self)))
        }
        guard let t = dict["type"] as? String else { return .failure(.missingType) }
        return .success(CoreMessage(t, dict))
    }
}
