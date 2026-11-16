/// Finds everything an answer says about ignore rules: in its prose, and in the .gitignore files it shows.
public struct IgnoreClaimReader: Sendable {
    /// Whether the lines of a .gitignore count as claims of their own (a ` # comment` after a pattern; a
    /// negated path that cannot come back).
    public let checksLines: Bool

    public init(checksLines: Bool = true) {
        self.checksLines = checksLines
    }

    /// Words that show a text is about ignore files. Without one of them (in the answer, or in the context a
    /// caller passes) a sentence such as "`[a-z]+` matches `abc`" is about something else, so the claims that
    /// rest only on the sentence's own patterns are not read.
    static let contextMarkers = ["gitignore", "git ignore", "ignore file", "ignore-file", "ignore rule",
                                 "ignore pattern", "check-ignore", "info/exclude", "excludesfile", "ignored by git",
                                 "git ignores"] + RuleBlocks.foreignFiles.map { String($0.dropFirst()) }

    /// Whether the text talks about .gitignore (or another tool's ignore file).
    public static func isAboutIgnoreRules(_ text: String) -> Bool {
        let folded = text.folded
        return contextMarkers.contains { folded.contains($0) }
    }

    /// The claims in an answer. `assumingIgnoreContext` says the conversation is already about ignore files
    /// (the question named `.gitignore`, say) when the answer itself does not.
    public func claims(in text: String, assumingIgnoreContext: Bool = false) -> [IgnoreClaim] {
        let found = allClaims(in: text)
        guard !assumingIgnoreContext, !Self.isAboutIgnoreRules(text) else { return found }
        return found.filter { if case .sentence = $0.source { false } else { true } }
    }

    /// The claims in an answer, given other text from the conversation (the question it answers). When that text
    /// names another tool's ignore file and nothing mentions .gitignore, the sentence's own patterns are that
    /// tool's rules, so its claims are left unchecked.
    public func claims(in text: String, context: String, assumingIgnoreContext: Bool = false) -> [IgnoreClaim] {
        let found = claims(in: text, assumingIgnoreContext: assumingIgnoreContext || Self.isAboutIgnoreRules(context))
        let folded = context.folded
        guard !(text.folded + folded).contains("gitignore"),
              let name = RuleBlocks.foreignFiles.first(where: { folded.contains($0) }) else { return found }
        return found.map { claim in if case .sentence = claim.source { claim.foreign(name) } else { claim } }
    }

    func allClaims(in text: String) -> [IgnoreClaim] {
        let blocks = AnswerBlocks.split(text)
        let ruleBlocks = RuleBlocks.find(in: blocks)
        let nested = ruleBlocks.filter { block in
            if case .gitignore(let directory) = block.kind { !directory.isEmpty } else { false }
        }
        var claims: [IgnoreClaim] = []
        for block in ruleBlocks where checksLines {
            if case .gitignore = block.kind {
                claims += LineReader.claims(in: block, rules: rules(for: block, nested: nested))
            }
        }
        for (position, block) in blocks.enumerated() where block.kind == .prose {
            let context = context(at: position, ruleBlocks, nested)
            for sentence in Sentences.split(block.lines) {
                claims += TrackingReader.claims(in: sentence, answer: text)
                claims += SentenceReader(context: context).claims(in: sentence)
            }
        }
        return Self.deduplicated(claims)
    }

    func rules(for block: RuleBlock, nested: [RuleBlock]) -> IgnoreRules {
        var files: [String: String] = [:]
        for other in nested + [block] {
            if case .gitignore(let directory) = other.kind { files[directory] = other.text }
        }
        return IgnoreRules(files: files)
    }

    /// The ignore file a sentence is about: the nearest root .gitignore (or other ignore file) before it, else
    /// the first one after it. Nested .gitignore files always apply.
    func context(at position: Int, _ ruleBlocks: [RuleBlock], _ nested: [RuleBlock]) -> ReadingContext {
        let roots = ruleBlocks.filter { !nested.contains($0) }
        guard let block = roots.last(where: { $0.position < position }) ?? roots.first ?? nested.last else {
            return ReadingContext(rules: nil, source: .none, blockLines: [])
        }
        let lines = Set(block.lines.map { IgnorePattern.trimmingTrailingSpaces($0.trimmed) }.filter { !$0.isEmpty })
        if case .foreign(let name) = block.kind {
            return ReadingContext(rules: nil, source: .foreign(name), blockLines: lines)
        }
        let allLines = nested.reduce(lines) { $0.union($1.lines.map(\.trimmed)) }
        return ReadingContext(rules: rules(for: block, nested: nested), source: .block(block.number),
                              blockLines: allLines)
    }

    /// One claim per subject and assertion: a sentence restating what a line already implies replaces it.
    static func deduplicated(_ claims: [IgnoreClaim]) -> [IgnoreClaim] {
        func key(_ claim: IgnoreClaim) -> String { "\(claim.kind)|\(claim.subject)|\(claim.assertion)" }
        let stated = Set(claims.filter(\.isExplicit).map(key))
        var seen: Set<String> = []
        return claims.filter { claim in
            (claim.isExplicit || !stated.contains(key(claim))) && seen.insert(key(claim)).inserted
        }
    }
}
