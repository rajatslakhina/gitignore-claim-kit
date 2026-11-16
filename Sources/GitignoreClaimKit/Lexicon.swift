/// The verbs and phrases that state whether something is ignored.
enum Lexicon {
    enum Polarity: Equatable {
        case ignored
        case kept
        /// "works" / "has no effect": said of a negated line.
        case works
    }

    static let ignoredVerbs: Set = ["ignores", "ignored", "ignore", "excludes", "excluded", "exclude", "matches",
                                    "matched", "match", "catches", "caught", "catch", "covers", "covered",
                                    "hides", "hidden", "untracked", "omitted", "omits"]
    static let keptVerbs: Set = ["re-includes", "re-included", "re-include", "reincludes", "reincluded",
                                 "reinclude",
                                 "un-ignores", "un-ignored", "un-ignore", "unignores", "unignored", "unignore",
                                 "whitelists", "whitelisted", "whitelist", "keeps", "kept", "tracked", "tracks",
                                 "track", "committed", "restores", "restored"]
    static let workVerbs: Set = ["works", "work", "effect", "nothing"]
    static let participles: Set = ["hidden", "kept", "caught", "untracked"]
    static let negations: Set = ["not", "never", "cannot", "nor", "neither"]
    static let skips: Set = ["should", "must", "need", "needs", "want", "wants", "try", "can", "could", "may",
                             "might", "to", "let", "lets", "help", "helps", "how", "please", "make", "makes"]
    static let beWords: Set = ["is", "are", "be", "been", "being", "stays", "stay", "remains", "remain", "gets",
                               "get", "still", "will", "won't", "isn't", "aren't", "was", "were", "also", "now",
                               "then", "only"]
    static let scopeAnywhere = ["at any depth", "any depth", "at any level", "at every level", "every level",
                                "any level", "anywhere", "everywhere", "in any directory", "in any folder",
                                "in every directory", "in every folder", "in all directories", "in all folders",
                                "in any subdirectory", "in any subfolder", "in every subdirectory", "recursively",
                                "throughout the repo", "throughout the repository", "throughout the project",
                                "no matter how deep", "however deep", "at all levels", "nested directories"]
    static let scopeTop = ["root", "top level", "top-level", "top of the repo", "repository root", "repo root"]

    /// A verb found in a clause.
    struct Verb {
        let index: Int
        let polarity: Polarity
        let word: String
    }

    /// The first verb in the tokens: its index and polarity. "brings back" and "shows up" count as one verb.
    static func verb(in tokens: [Clause.Token]) -> Verb? {
        for (index, token) in tokens.enumerated() {
            guard case .word(let word) = token else { continue }
            let next = index + 1 < tokens.count ? Self.word(tokens[index + 1]) : nil
            if ignoredVerbs.contains(word) { return Verb(index: index, polarity: .ignored, word: word) }
            if keptVerbs.contains(word) { return Verb(index: index, polarity: .kept, word: word) }
            if ["brings", "bring", "brought"].contains(word),
               tokens[(index + 1)...].prefix(3).contains(.word("back")) {
                return Verb(index: index, polarity: .kept, word: word)
            }
            if ["shows", "show", "appears", "appear"].contains(word), next == "up" || next == "in" {
                return Verb(index: index, polarity: .kept, word: word)
            }
            if ["works", "work"].contains(word) { return Verb(index: index, polarity: .works, word: word) }
            if word == "has", next == "no" { return Verb(index: index, polarity: .works, word: "no-effect") }
            if word == "does", next == "nothing" { return Verb(index: index, polarity: .works, word: "no-effect") }
        }
        return nil
    }

    static func word(_ token: Clause.Token) -> String? {
        if case .word(let word) = token { word } else { nil }
    }

    static func isNegation(_ word: String) -> Bool {
        negations.contains(word) || word.hasSuffix("n't")
    }

    /// How many negations the words hold; "no longer" counts, a bare "no" ("no slash") does not.
    static func negationCount(_ words: [String]) -> Int {
        words.indices.filter { index in
            isNegation(words[index]) || words[index] == "no" && index + 1 < words.count && words[index + 1] == "longer"
        }.count
    }
}
