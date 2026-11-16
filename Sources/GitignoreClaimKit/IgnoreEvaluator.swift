/// Applies git's rules to a claim.
struct IgnoreEvaluator {
    let policy: IgnorePolicy

    /// The misreadings tried, in order, to name the slip behind a wrong claim, each with the claim it can explain
    /// (`true`: "is ignored", `false`: "is kept", `nil`: either).
    struct Misreading {
        let reading: Reading
        let slip: IgnoreFinding.Slip
        let explains: Bool?
    }

    static let misreadings = [
        Misreading(reading: .trailingComments, slip: .trailingComment, explains: true),
        Misreading(reading: .parentExclusionIgnored, slip: .reincludeUnderExcludedDirectory, explains: false),
        Misreading(reading: .directoryOnlyMatchesFiles, slip: .directoryOnly, explains: true),
        Misreading(reading: .anchoredMatchesAnywhere, slip: .slashAnchors, explains: true),
        Misreading(reading: .slashlessIsRootOnly, slip: .slashlessMatchesEverywhere, explains: false),
        Misreading(reading: .doubleStarNeedsDirectory, slip: .doubleStarMatchesZero, explains: false),
        Misreading(reading: .starCrossesSlash, slip: .starStopsAtSlash, explains: true),
        Misreading(reading: .starSkipsDotfiles, slip: .starMatchesDotfiles, explains: false),
        Misreading(reading: .firstMatchWins, slip: .lastMatchWins, explains: nil)
    ]

    func judge(_ claim: IgnoreClaim) -> IgnoreFinding {
        if case .foreign(let name) = claim.source {
            return IgnoreFinding(claim: claim, outcome: .unchecked("\(name) follows its own tool's rules, not git's"))
        }
        switch claim.kind {
        case .tracking:
            let outcome: IgnoreFinding.Outcome = claim.assertion == .untracks ? .wrong(.alreadyTracked) : .exact
            return IgnoreFinding(claim: claim, outcome: outcome)
        case .line:
            return judgeLine(claim)
        case .scope:
            return judgeScope(claim)
        case .path:
            return judgePath(claim)
        }
    }

    func judgePath(_ claim: IgnoreClaim) -> IgnoreFinding {
        guard let rules = claim.rules else {
            return IgnoreFinding(claim: claim, outcome: .unchecked("no .gitignore to check it against"))
        }
        let (path, slashed) = IgnoreRules.normalize(claim.subject)
        let claimed = claim.assertion == .ignored
        let asFile = decide(rules, path, false)
        let asDirectory = decide(rules, path, true)
        let isDirectory: Bool
        if slashed || claim.isDirectory == true {
            isDirectory = true
        } else if claim.isDirectory == false || asFile == asDirectory || Self.hasExtension(path) {
            isDirectory = false
        } else {
            return IgnoreFinding(claim: claim, outcome: .unchecked(
                "`\(path)` reads differently as a file and as a directory; write `\(path)/` for the directory"))
        }
        guard let ignored = isDirectory ? asDirectory : asFile else {
            let verdict = rules.verdict(path, isDirectory: isDirectory, ignoreCase: false, reading: [])
            let holdsWhen = verdict.isIgnored == claimed ? false : true
            let outcome: IgnoreFinding.Outcome = policy.reportsCaveats
                ? .caveat(.dependsOnIgnoreCase(holdsWhen: holdsWhen)) : .exact
            return IgnoreFinding(claim: claim, outcome: outcome, verdict: verdict)
        }
        let verdict = rules.verdict(path, isDirectory: isDirectory, ignoreCase: policy.ignoreCase ?? false,
                                    reading: [])
        guard ignored != claimed else { return IgnoreFinding(claim: claim, outcome: .exact, verdict: verdict) }
        let ignoreCase = policy.ignoreCase ?? false
        let misread = Self.misreadings.lazy.compactMap { misreading -> (IgnoreFinding.Slip, IgnoreVerdict)? in
            guard misreading.explains != !claimed else { return nil }
            let other = rules.verdict(path, isDirectory: isDirectory, ignoreCase: ignoreCase,
                                      reading: misreading.reading)
            return other.isIgnored == claimed ? (misreading.slip, other) : nil
        }.first
        let line = verdict.decidingPattern ?? misread?.1.decidingPattern
        let caseSlip = misread == nil
            && rules.verdict(path, isDirectory: isDirectory, ignoreCase: !ignoreCase, reading: []).isIgnored == claimed
        if caseSlip { return IgnoreFinding(claim: claim, outcome: .wrong(.letterCase), verdict: verdict) }
        return IgnoreFinding(claim: claim, outcome: .wrong(misread?.0), verdict: verdict,
                             fix: Fixes.fix(for: misread?.0, line: line, verdict: verdict, path: path))
    }

    /// git's answer for `path`, or `nil` when it depends on `core.ignorecase` and the policy does not say.
    func decide(_ rules: IgnoreRules, _ path: String, _ isDirectory: Bool) -> Bool? {
        if let ignoreCase = policy.ignoreCase {
            return rules.verdict(path, isDirectory: isDirectory, ignoreCase: ignoreCase, reading: []).isIgnored
        }
        let sensitive = rules.verdict(path, isDirectory: isDirectory, ignoreCase: false, reading: []).isIgnored
        let folded = rules.verdict(path, isDirectory: isDirectory, ignoreCase: true, reading: []).isIgnored
        return sensitive == folded ? sensitive : nil
    }

    /// `a/b.txt` and `.env.local` have one; `Makefile` and `.env` do not.
    static func hasExtension(_ path: String) -> Bool {
        guard let name = path.split(separator: "/").last else { return false }
        return name.dropFirst().contains(".")
    }

    func judgeScope(_ claim: IgnoreClaim) -> IgnoreFinding {
        guard let pattern = IgnorePattern(line: claim.subject, lineNumber: 1, directory: ""),
              let sample = Samples.path(for: pattern) else {
            return IgnoreFinding(claim: claim, outcome: .unchecked("no sample path could be built for the pattern"))
        }
        let deeper = "sub/" + sample
        let probe = deeper.hasSuffix("/") ? String(deeper.dropLast()) : deeper
        let matchesDeeper = pattern.matches(probe, isDirectory: pattern.isDirectoryOnly, ignoreCase: false)
        let holds = (claim.assertion == .anyDepth) == matchesDeeper
        guard !holds else { return IgnoreFinding(claim: claim, outcome: .exact, example: deeper) }
        let slip: IgnoreFinding.Slip = matchesDeeper ? .slashlessMatchesEverywhere : .slashAnchors
        let body = IgnorePattern.unrooted(claim.subject)
        let fix = matchesDeeper ? "/" + body : "**/" + body
        return IgnoreFinding(claim: claim, outcome: .wrong(slip), example: deeper, fix: fix)
    }

    func judgeLine(_ claim: IgnoreClaim) -> IgnoreFinding {
        let intended = IgnorePattern.withoutTrailingComment(claim.subject)
        let example = IgnorePattern(line: intended, lineNumber: 1, directory: "").flatMap(Samples.path)
        return IgnoreFinding(claim: claim, outcome: .wrong(.trailingComment), example: example, fix: intended)
    }
}

/// A line that does what a wrong claim expected.
enum Fixes {
    static func fix(for slip: IgnoreFinding.Slip?, line: IgnorePattern?, verdict: IgnoreVerdict,
                    path: String) -> String? {
        guard let slip, let line else { return nil }
        switch slip {
        case .reincludeUnderExcludedDirectory:
            return reinclude(line, verdict, path)
        case .trailingComment:
            return IgnorePattern.withoutTrailingComment(line.line)
        case .directoryOnly:
            return line.body
        case .slashAnchors:
            return "**/" + IgnorePattern.unrooted(line.body)
        case .slashlessMatchesEverywhere:
            return "/" + line.body + (line.isDirectoryOnly ? "/" : "")
        case .starStopsAtSlash:
            return line.body.replacingOccurrences(of: "/*", with: "/**/*")
        default:
            return nil
        }
    }
}

extension Fixes {
    /// `logs/` -> `logs/*`, which ignores the contents but leaves the directory open, when the file sits
    /// directly in that directory.
    static func reinclude(_ line: IgnorePattern, _ verdict: IgnoreVerdict, _ path: String) -> String? {
        guard let parent = verdict.excludedParent, line.directory.isEmpty,
              IgnorePattern.unrooted(line.body) + "/" == parent,
              !path.dropFirst(parent.count).contains("/") else { return nil }
        return (line.body.hasPrefix("/") ? "/" : "") + parent + "*"
    }
}

/// A path a pattern matches, for showing what a scope claim means.
enum Samples {
    static func path(for pattern: IgnorePattern) -> String? {
        var body = IgnorePattern.unrooted(pattern.body)
        body = body.replacingOccurrences(of: "**/", with: "")
        if body.hasSuffix("/**") { body = String(body.dropLast(2)) + "x" }
        var result = ""
        var characters = ArraySlice(body)
        while let character = characters.popFirst() {
            switch character {
            case "*": if characters.first != "*" { result.append("x") }
            case "?": result.append("x")
            case "\\": if let next = characters.popFirst() { result.append(next) }
            case "[":
                guard let (first, rest) = bracket(characters) else { return nil }
                result.append(first)
                characters = rest
            default: result.append(character)
            }
        }
        return checked(result, pattern)
    }

    /// The first member of a bracket (`[ab]` gives `a`) and what follows it; `nil` for a negated, nested or
    /// unterminated bracket.
    static func bracket(_ characters: ArraySlice<Character>) -> (Character, ArraySlice<Character>)? {
        guard let close = characters.firstIndex(of: "]") else { return nil }
        let inner = characters[characters.startIndex..<close]
        guard let first = inner.first, !"!^[".contains(first) else { return nil }
        return (first, characters[(close + 1)...])
    }

    /// The sample, if the pattern really matches it.
    static func checked(_ result: String, _ pattern: IgnorePattern) -> String? {
        let sample = result.replacingOccurrences(of: "//", with: "/")
        let matched = !sample.isEmpty
            && pattern.matches(sample, isDirectory: pattern.isDirectoryOnly, ignoreCase: false)
        return matched ? sample + (pattern.isDirectoryOnly ? "/" : "") : nil
    }
}
