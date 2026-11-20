import Foundation

/// Matches a spoken answer to a question's option labels (#19). Pure, so the self-test covers it.
/// "Detailed, please" → ["Detailed"]; "the second one" → the second label; "both" (multi-select) → all.
/// No match → [] (the app then sends the spoken text itself as a typed answer).
public enum OptionMatch {
    // No "one": in speech it is usually "the second one", not a position.
    static let ordinals = ["first": 0, "1st": 0, "second": 1, "two": 1, "2nd": 1,
                           "third": 2, "three": 2, "3rd": 2, "fourth": 3, "four": 3, "4th": 3]

    static func words(_ s: String) -> [String] {
        s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    public static func match(_ spoken: String, labels: [String], multiSelect: Bool) -> [String] {
        let said = words(spoken)
        guard !said.isEmpty else { return [] }
        let saidText = " " + said.joined(separator: " ") + " "
        if multiSelect, said.contains(where: { ["both", "all", "everything"].contains($0) }) { return labels }
        // A label counts if all of its words were said, in order.
        var hits = labels.filter { label in
            let lw = words(label)
            return !lw.isEmpty && saidText.contains(" " + lw.joined(separator: " ") + " ")
        }
        if hits.isEmpty {
            let idx = said.compactMap { ordinals[$0] }.filter { $0 < labels.count }
            hits = idx.map { labels[$0] }
            if said.contains("last"), let l = labels.last { hits.append(l) }
        }
        var seen = Set<String>()
        hits = hits.filter { seen.insert($0).inserted }
        return multiSelect ? hits : (hits.count == 1 ? hits : [])   // two labels for a single choice: ambiguous
    }
}
