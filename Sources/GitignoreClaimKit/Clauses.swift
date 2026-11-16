/// A clause of a sentence: its words in order, with each inline code span as one token.
struct Clause {
    enum Token: Equatable {
        case word(String)
        case span(Int)
    }

    let tokens: [Token]
    /// Split off after "and" or "but", so a missing subject is the previous clause's.
    let continues: Bool

    var words: [String] {
        tokens.compactMap { if case .word(let word) = $0 { word } else { nil } }
    }

    func spans(in range: Range<Int>) -> [Int] {
        tokens[range].compactMap { if case .span(let index) = $0 { index } else { nil } }
    }
}

enum Clauses {
    static let conditions: Set = ["if", "unless", "when", "whenever", "provided", "assuming", "once", "otherwise",
                                  "else", "suppose", "imagine"]
    static let strongBreaks: Set = [";", "but", "while", "whereas", "so", "because", "since", "although", "though",
                                    "then"]

    /// The sentence's clauses, each cut at its first condition ("if", "unless", "when", ...).
    static func split(_ pieces: [(text: String, isCode: Bool)]) -> [Clause] {
        var all: [Clause.Token] = []
        var spanIndex = 0
        for piece in pieces {
            if piece.isCode {
                all.append(.span(spanIndex))
                spanIndex += 1
            } else {
                all += words(piece.text).map(Clause.Token.word)
            }
        }
        var clauses: [Clause] = []
        var current: [Clause.Token] = []
        var continues = false
        func flush(_ next: Bool) {
            if !current.isEmpty { clauses.append(Clause(tokens: cut(current), continues: continues)) }
            current = []
            continues = next
        }
        for (index, token) in all.enumerated() {
            if case .word(let word) = token {
                if word == ";" || word == "," && index + 1 < all.count && all[index + 1] == .word("but") {
                    flush(false)
                    continue
                }
                if strongBreaks.contains(word), !current.isEmpty {
                    flush(true)
                    continue
                }
                if ["and", "or", ","].contains(word), verbAhead(all, index), Lexicon.verb(in: current) != nil {
                    flush(true)
                    continue
                }
            }
            current.append(token)
        }
        flush(false)
        return clauses.filter { !$0.tokens.isEmpty }
    }

    static func verbAhead(_ tokens: [Clause.Token], _ index: Int) -> Bool {
        Lexicon.verb(in: Array(tokens[(index + 1)...])) != nil
    }

    /// The clause up to its first condition word.
    static func cut(_ tokens: [Clause.Token]) -> [Clause.Token] {
        guard let stop = tokens.firstIndex(where: { token in
            if case .word(let word) = token { conditions.contains(word) } else { false }
        }) else { return tokens }
        return Array(tokens[..<stop])
    }

    /// Lowercased words; `,` and `;` kept as words of their own; other punctuation dropped.
    static func words(_ text: String) -> [String] {
        var result: [String] = []
        var word = ""
        for character in text.folded {
            if character.isLetter || character.isNumber || "'-".contains(character) {
                word.append(character)
            } else {
                if !word.isEmpty { result.append(word) }
                word = ""
                if character == "," || character == ";" { result.append(String(character)) }
            }
        }
        if !word.isEmpty { result.append(word) }
        return result
    }
}
