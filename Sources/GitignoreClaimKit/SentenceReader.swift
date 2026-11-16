/// The rules a sentence is read against.
struct ReadingContext {
    let rules: IgnoreRules?
    let source: IgnoreClaim.Source
    /// The lines of the .gitignore in view, trimmed: a code span equal to one is a pattern.
    let blockLines: Set<String>
}

/// Reads the claims one sentence of prose makes about ignore rules.
struct SentenceReader {
    let context: ReadingContext

    func claims(in sentence: String) -> [IgnoreClaim] {
        guard !sentence.hasSuffix("?") else { return [] }
        let pieces = Sentences.pieces(sentence)
        let spans = Span.read(pieces, blockLines: context.blockLines)
        let folded = sentence.folded
        let foreign = RuleBlocks.foreignFiles.first { folded.contains($0) }
        let local = foreign.map { ReadingContext(rules: nil, source: .foreign($0), blockLines: []) } ?? context
        var claims: [IgnoreClaim] = []
        var previousSubjects: [Span] = []
        for (number, clause) in Clauses.split(pieces).enumerated() {
            guard let verb = Lexicon.verb(in: clause.tokens) else {
                claims += Self.anchoring(clause, spans, sentence)
                continue
            }
            var subjects = clause.spans(in: 0..<verb.index).map { spans[$0] }
                .filter { !$0.isContrasted && !$0.isContainer }
            let objects = clause.spans(in: (verb.index + 1)..<clause.tokens.count).map { spans[$0] }
                .filter { !$0.isContrasted }
            let before = Array(clause.words.prefix(wordIndex(clause, verb.index)))
            let bare = clause.spans(in: 0..<verb.index).isEmpty
                && before.allSatisfy { Lexicon.beWords.contains($0) || Lexicon.isNegation($0) }
            if bare, clause.continues { subjects = previousSubjects }
            previousSubjects = subjects
            if number == 0, before.isEmpty, subjects.isEmpty, !clause.continues { continue }
            if Self.isHedged(before) { continue }
            let reading = ClauseFacts(clause: clause, verb: verb, before: before, subjects: subjects, objects: objects)
            claims += Self.claims(reading, sentence: sentence, context: local, spans: spans)
        }
        return foreign.map { name in claims.map { $0.foreign(name) } } ?? claims
    }

    /// How many words precede the token at `tokenIndex`.
    func wordIndex(_ clause: Clause, _ tokenIndex: Int) -> Int {
        clause.tokens[..<tokenIndex].filter { if case .word = $0 { true } else { false } }.count
    }

    /// "`doc/*.txt` is anchored to its directory" (no verb of matching, but a scope all the same).
    static func anchoring(_ clause: Clause, _ spans: [Span], _ sentence: String) -> [IgnoreClaim] {
        let words = clause.words
        guard let at = words.firstIndex(of: "anchored") else { return [] }
        let subjects = clause.spans(in: 0..<clause.tokens.count).map { spans[$0] }
            .filter { ($0.role == .pattern || $0.role == .path) && !$0.isContrasted }
        guard subjects.count == 1 else { return [] }
        let negated = Lexicon.negationCount(Array(words[..<at])) % 2 == 1
        let pattern = subjects[0].text
        return [IgnoreClaim(kind: .scope, subject: pattern, assertion: negated ? .anyDepth : .topLevelOnly,
                            sentence: sentence, source: .sentence([pattern]), rules: IgnoreRules(pattern + "\n"))]
    }

    /// "should be ignored", "to ignore", "can keep": advice, purpose or ability, not a statement of fact. Forms
    /// of "be" and negations between the word and the verb are skipped over ("must not be ignored").
    static func isHedged(_ before: [String]) -> Bool {
        var index = before.count - 1
        while index >= 0, !Lexicon.skips.contains(before[index]),
              Lexicon.beWords.contains(before[index]) || Lexicon.isNegation(before[index]) {
            index -= 1
        }
        return index >= 0 && Lexicon.skips.contains(before[index])
    }

    /// The patterns a sentence names that rules can be made of for `subject`: globs, negations, lines of the
    /// .gitignore in view, and directories that contain the subject (`logs/` for `logs/keep.log`).
    static func sentencePatterns(_ spans: [Span], for subject: String) -> [String] {
        spans.filter { span in
            guard !span.isContrasted, span.path != subject else { return false }
            if span.role == .pattern || span.role == .negation { return true }
            let directory = span.path.hasSuffix("/") ? span.path : span.path + "/"
            return span.role == .path && subject.hasPrefix(directory)
        }.map(\.text)
    }

    static func claims(_ facts: ClauseFacts, sentence: String, context: ReadingContext,
                       spans: [Span]) -> [IgnoreClaim] {
        let ruleSubjects = facts.subjects.filter { $0.role == .pattern || $0.role == .path || $0.role == .negation }
        var claims: [IgnoreClaim] = []
        if let scope = facts.scope, ruleSubjects.count == 1, ruleSubjects[0].role != .negation {
            let pattern = ruleSubjects[0].text
            claims.append(IgnoreClaim(kind: .scope, subject: pattern, assertion: scope, sentence: sentence,
                                      source: .sentence([pattern]), rules: IgnoreRules(pattern + "\n")))
        }
        guard let assertion = facts.assertion else { return claims }
        let read = ClauseClaims(facts: facts, sentence: sentence, context: context, spans: spans,
                                assertion: assertion, ruleSubjects: ruleSubjects)
        return claims + read.exceptions() + read.paths()
    }

    static func pathClaim(_ span: Span, _ assertion: IgnoreClaim.Assertion, _ sentence: String,
                          _ source: IgnoreClaim.Source, _ rules: IgnoreRules?) -> IgnoreClaim {
        IgnoreClaim(kind: .path, subject: span.path, assertion: assertion, sentence: sentence, source: source,
                    rules: rules, isDirectory: span.isDirectoryHint)
    }

    /// The answer's .gitignore if it has one, else the patterns the sentence names.
    static func fallback(_ context: ReadingContext, _ patterns: [String]) -> (IgnoreClaim.Source, IgnoreRules?) {
        if context.rules != nil || context.source != .none { return (context.source, context.rules) }
        guard !patterns.isEmpty else { return (.none, nil) }
        let rules = sentenceRules(patterns)
        return (.sentence(rules.lines), rules.rules)
    }

    static func sentenceRules(_ patterns: [String]) -> (lines: [String], rules: IgnoreRules) {
        let ordered = patterns.filter { !$0.hasPrefix("!") } + patterns.filter { $0.hasPrefix("!") }
        return (ordered, IgnoreRules(ordered.joined(separator: "\n") + "\n"))
    }

    /// The path a negated line names when it has no wildcards: `!logs/keep.log` names `logs/keep.log`.
    static func literal(_ negation: String) -> String? {
        let body = String(negation.dropFirst())
        guard !body.isEmpty, !body.contains(where: { "*?[\\".contains($0) }) else { return nil }
        return body
    }
}

/// What one clause says, once its verb, negation and spans are known.
struct ClauseFacts {
    let clause: Clause
    let verb: Lexicon.Verb
    /// The words before the verb.
    let before: [String]
    let subjects: [Span]
    let objects: [Span]

    var text: String { clause.words.joined(separator: " ") }

    /// Negated once (or an odd number of times) between the subject and the verb.
    var isNegated: Bool {
        let lastSubject = clause.tokens[..<verb.index].lastIndex { if case .span = $0 { true } else { false } }
        let start = lastSubject.map { $0 + 1 } ?? 0
        let words = clause.tokens[start..<verb.index].compactMap(Lexicon.word)
        let count = Lexicon.negationCount(words) + (verb.word == "no-effect" ? 1 : 0)
        return count % 2 == 1
    }

    /// Ignored or not, from the verb and its negation; "keeps ... out" means ignored.
    var assertion: IgnoreClaim.Assertion? {
        let after = clause.tokens[(verb.index + 1)...].compactMap(Lexicon.word)
        var ignored = verb.polarity == .ignored
        if verb.polarity == .kept, ["keeps", "kept"].contains(verb.word), after.contains("out") { ignored = true }
        if verb.polarity == .works { ignored = false }
        if isNegated { ignored.toggle() }
        return ignored ? .ignored : .notIgnored
    }

    /// "`logs/keep.log` is ignored": a participle with a form of "be" (or "stays", "gets") before it.
    var isPassive: Bool {
        let participle = verb.word.hasSuffix("ed") || Lexicon.participles.contains(verb.word)
        return participle && before.last.map { Lexicon.beWords.contains($0) || Lexicon.isNegation($0) } == true
    }

    /// Any depth or top level only, when the clause says either.
    var scope: IgnoreClaim.Assertion? {
        let text = " " + self.text + " "
        let anywhere = Lexicon.scopeAnywhere.contains { text.contains(" " + $0 + " ") }
        let only = ["only", "just", "solely"].contains { clause.words.contains($0) }
        let top = only && Lexicon.scopeTop.contains { text.contains(" " + $0 + " ") }
        let anchored = clause.words.contains("anchored")
        guard anywhere || top || anchored else { return nil }
        let after = clause.tokens[(verb.index + 1)...].prefix(2).compactMap(Lexicon.word)
        let negated = (isNegated != (verb.word == "no-effect")) != (Lexicon.negationCount(after) % 2 == 1)
        let deep = anywhere && !top
        return deep != negated ? .anyDepth : .topLevelOnly
    }
}

/// The path claims of one clause, once its assertion is known.
struct ClauseClaims {
    let facts: ClauseFacts
    let sentence: String
    let context: ReadingContext
    let spans: [Span]
    let assertion: IgnoreClaim.Assertion
    let ruleSubjects: [Span]

    var objects: [Span] {
        facts.objects.filter { $0.role == .path && !$0.isContainer && !$0.isException }
    }

    func claim(_ span: Span, _ assertion: IgnoreClaim.Assertion, _ source: IgnoreClaim.Source,
               _ rules: IgnoreRules?) -> IgnoreClaim {
        SentenceReader.pathClaim(span, assertion, sentence, source, rules)
    }

    /// "Everything in `logs/` is ignored except `logs/.gitkeep`": an exception is kept.
    func exceptions() -> [IgnoreClaim] {
        guard context.rules != nil, facts.verb.polarity == .ignored else { return [] }
        let flipped: IgnoreClaim.Assertion = assertion == .ignored ? .notIgnored : .ignored
        return facts.objects.filter { $0.role == .path && $0.isException }
            .map { claim($0, flipped, context.source, context.rules) }
    }

    func paths() -> [IgnoreClaim] {
        let negated = ruleSubjects.contains { $0.role == .negation }
        if !objects.isEmpty, !ruleSubjects.isEmpty, facts.verb.polarity != .works, !facts.isPassive, !negated {
            // "`doc/*.txt` matches `doc/a/b.txt`": the subjects are the rules.
            let rules = SentenceReader.sentenceRules(ruleSubjects.map(\.text))
            return objects.map { claim($0, assertion, .sentence(rules.lines), rules.rules) }
        }
        if !objects.isEmpty, ruleSubjects.isEmpty, facts.verb.polarity != .works,
           context.rules != nil || context.source != .none {
            // "This ignores `logs/app.log`": the rules are the answer's .gitignore.
            return objects.map { claim($0, assertion, context.source, context.rules) }
        }
        if facts.isPassive, facts.verb.polarity != .works { return passive() }
        return negation()
    }

    /// "`logs/keep.log` stays ignored".
    func passive() -> [IgnoreClaim] {
        facts.subjects.filter { $0.role == .path }.compactMap { subject in
            let patterns = SentenceReader.sentencePatterns(spans, for: subject.path)
            let (source, rules) = SentenceReader.fallback(context, patterns)
            return rules != nil || source != .none ? claim(subject, assertion, source, rules) : nil
        }
    }

    /// "`!logs/keep.log` keeps that file" / "... has no effect".
    func negation() -> [IgnoreClaim] {
        guard let last = ruleSubjects.last, last.role == .negation, facts.verb.polarity != .ignored,
              let literal = SentenceReader.literal(last.text) else { return [] }
        let span = Span(text: literal, role: .path, lead: "", tail: "")
        if context.blockLines.contains(last.text) { return [claim(span, assertion, context.source, context.rules)] }
        let patterns = SentenceReader.sentencePatterns(spans, for: literal)
        guard patterns.count > 1 else { return [] }
        let rules = SentenceReader.sentenceRules(patterns)
        return [claim(span, assertion, .sentence(rules.lines), rules.rules)]
    }
}
