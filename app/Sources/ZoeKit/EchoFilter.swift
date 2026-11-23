import Foundation

/// Is a transcript just Zoe hearing itself? (#22 follow-up, #36–#38 run: "it listens to its own voice and
/// replies"). Pure, so the self-test covers it. Half-duplex already ignores the mic while Zoe speaks; this
/// catches what slips through: the tail of a reply still sounding from the speakers when listening resumes.
///
/// - Several words: echo if at least 75 % of them were in what Zoe said in the last few seconds.
/// - One or two words: echo only if they match the *end* of what Zoe said, so a real "yes" or "no" survives.
public enum EchoFilter {
    static func words(_ s: String) -> [String] {
        s.lowercased().replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
    }

    public static func isEcho(_ transcript: String, recentSpeech: String) -> Bool {
        let t = words(transcript), r = words(recentSpeech)
        guard !t.isEmpty, !r.isEmpty else { return false }
        if t.count <= 2 { return Array(r.suffix(4)).containsInOrder(t) }
        let said = Set(r)
        let hits = t.filter(said.contains).count
        return Double(hits) / Double(t.count) >= 0.75
    }
}

extension Array where Element == String {
    func containsInOrder(_ sub: [String]) -> Bool {
        guard !sub.isEmpty, sub.count <= count else { return false }
        for i in 0...(count - sub.count) where Array(self[i..<(i + sub.count)]) == sub { return true }
        return false
    }
}
