/// Claims a .gitignore makes by its lines alone: a pattern with a ` # comment` after it is meant to work, and a
/// negated path is meant to stay in the repository.
enum LineReader {
    static func claims(in block: RuleBlock, rules: IgnoreRules) -> [IgnoreClaim] {
        guard case .gitignore(let directory) = block.kind, !block.isCounterexample else { return [] }
        var claims: [IgnoreClaim] = []
        for raw in block.lines {
            let line = raw.trimmingCharacters(in: .newlines)
            guard !line.hasPrefix("#"), !line.trimmed.isEmpty else { continue }
            if IgnorePattern.trailingComment(in: line) != nil {
                claims.append(IgnoreClaim(kind: .line, subject: line, assertion: .takesEffect, sentence: line,
                                          isExplicit: false, source: .block(block.number), rules: rules))
                continue
            }
            let trimmed = IgnorePattern.trimmingTrailingSpaces(line)
            guard trimmed.hasPrefix("!"), let literal = SentenceReader.literal(trimmed) else { continue }
            let path = directory + IgnorePattern.unrooted(literal)
            let isDirectory: Bool? = path.hasSuffix("/") ? true : IgnoreEvaluator.hasExtension(path) ? false : nil
            claims.append(IgnoreClaim(kind: .path, subject: path, assertion: .notIgnored, sentence: line,
                                      isExplicit: false, source: .block(block.number), rules: rules,
                                      isDirectory: isDirectory))
        }
        return claims
    }
}
