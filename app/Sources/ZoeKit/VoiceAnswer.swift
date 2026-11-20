import Foundation

/// A spoken answer to an approval card (#17, PLAN.md §7.7). Pure, so the self-test covers it.
///
/// - Only short answers count: "yes", "sure, go ahead", "no", "cancel that". Anything longer, or with no
///   yes/no word, is `.unclear` (Zoe asks once more, then waits for a click).
/// - A "no" word anywhere wins: "yes, cancel it" is a no. Mishearing a no as a yes is the dangerous mistake.
/// - An answer counts only if the speech *started after* the prompt finished (`accepted`).
public enum VoiceAnswer: Sendable, Equatable {
    case yes, no, unclear

    static let yesWords: Set<String> = ["yes", "yeah", "yep", "yup", "sure", "ok", "okay", "approve", "approved",
                                        "confirm", "confirmed", "correct", "absolutely", "definitely"]
    static let yesPhrases = ["go ahead", "do it", "send it", "sounds good", "please do", "that's fine", "thats fine"]
    static let noWords: Set<String> = ["no", "nope", "nah", "cancel", "stop", "deny", "denied", "don't", "dont",
                                       "wait", "never", "not", "negative", "abort", "hold"]
    /// Longer than this, it's a sentence, not an answer.
    public static let maxWords = 6

    public static func classify(_ text: String) -> VoiceAnswer {
        let norm = text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.letters.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
        guard !norm.isEmpty else { return .unclear }
        if norm.contains(where: noWords.contains) { return .no }
        guard norm.count <= maxWords else { return .unclear }
        let joined = norm.joined(separator: " ")
        if norm.contains(where: yesWords.contains) || yesPhrases.contains(where: joined.contains) { return .yes }
        return .unclear
    }

    /// Speech that began before the prompt finished (or within `margin` after, the echo tail) doesn't count.
    public static func accepted(speechStart: TimeInterval, promptEnd: TimeInterval, margin: TimeInterval = 0.1) -> Bool {
        speechStart >= promptEnd + margin
    }
}
