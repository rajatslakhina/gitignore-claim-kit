/// Splits prose into sentences, and sentences into prose and inline code.
enum Sentences {
    static func split(_ lines: [String]) -> [String] {
        var sentences: [String] = []
        for line in lines {
            var current = ""
            let characters = Array(line)
            for (index, character) in characters.enumerated() {
                current.append(character)
                // A stop ends a sentence only before a space or the end of the line: `app.log` stays whole.
                let ends = index + 1 == characters.count || characters[index + 1].isWhitespace
                let abbreviation = ["vs.", "e.g.", "i.e.", "etc."].contains { current.lowercased().hasSuffix($0) }
                if ".!?".contains(character), ends, !abbreviation, current.filter({ $0 == "`" }).count % 2 == 0 {
                    sentences.append(current)
                    current = ""
                }
            }
            sentences.append(current)
        }
        return sentences.map(\.trimmed).filter { !$0.isEmpty }
    }

    /// The sentence cut at its backticks: even pieces are prose, odd pieces are inline code.
    static func pieces(_ sentence: String) -> [(text: String, isCode: Bool)] {
        sentence.components(separatedBy: "`").enumerated().map { ($0.element, $0.offset % 2 == 1) }
    }
}
