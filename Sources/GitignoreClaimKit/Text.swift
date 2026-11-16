import Foundation

extension StringProtocol {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The text with curly apostrophes made straight and letters lowercased, for matching phrases.
    var folded: String {
        lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
    }
}

enum Words {
    /// Whether `phrase` occurs in `text` without running into a neighbouring word: `pip` is found in
    /// "use pip to" but not in "pipeline". An edge of the phrase that is punctuation needs no boundary.
    static func contains(_ text: String, _ phrase: String) -> Bool {
        var start = text.startIndex
        while let range = text.range(of: phrase, range: start..<text.endIndex) {
            if bounded(text, range, phrase) { return true }
            start = text.index(after: range.lowerBound)
        }
        return false
    }

    static func bounded(_ text: String, _ range: Range<String.Index>, _ phrase: String) -> Bool {
        let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
        let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
        let opensClean = !isWord(phrase.first) || !isWord(before)
        let closesClean = !isWord(phrase.last) || !isWord(after)
        return opensClean && closesClean
    }

    static func isWord(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber || character == "_"
    }

    /// Whether any of the phrases occurs in the text as words.
    static func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { contains(text, $0) }
    }
}
