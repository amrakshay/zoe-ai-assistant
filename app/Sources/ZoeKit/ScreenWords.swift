import Foundation

/// Does a request point at the screen (#42)? "What's this error?", "summarise that", "on my screen", "the
/// selected text"; but not "this afternoon" or "that meeting tomorrow". Pure, so the self-test covers it.
/// A false positive costs a taint (going online then asks), so time phrases are excluded.
public enum ScreenWords {
    // "this / that / these / those" only alone ("fix this", "summarise that?") or before a screen-ish word,
    // so "that meeting tomorrow" or "this afternoon" don't count.
    static let nouns = "error|errors|message|messages|page|code|text|email|mail|file|document|doc|thread|window|tab|function|" +
        "method|line|lines|screenshot|chart|table|link|article|post|issue|bug|warning|output|log|logs|reply|paragraph|" +
        "sentence|word|selection|diff|command|image|picture|photo|exception|stack|trace|test|query|snippet|part|bit|one"
    static let verbs = "is|are|was|were|mean|means|does|do|say|says|show|shows|right|correct|wrong|ok|okay|true|good|fine"
    static let pattern = try! NSRegularExpression(pattern:
        #"\b(?:this|that|these|those)\b(?=\s*(?:[?.!,;:]|$|(?:"# + nouns + "|" + verbs + #")\b))"# +
        #"|\bhere\b|\bon (?:my |the )?screen\b|\bselect(?:ed|ion)\b|\bhighlighted\b|\bfront(?:most)? (?:window|app)\b"#,
        options: [.caseInsensitive])

    public static func mentionsScreen(_ text: String) -> Bool {
        pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
