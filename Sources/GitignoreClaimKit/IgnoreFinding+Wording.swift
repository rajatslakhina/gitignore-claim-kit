extension IgnoreFinding {
    /// One or two sentences for the person reading the answer.
    public var explanation: String {
        switch outcome {
        case .exact:
            return confirmation
        case .caveat(.dependsOnIgnoreCase(let holdsWhen)):
            let setting = holdsWhen ? "true (the default for a repository created on macOS or Windows)"
                : "false (the default on Linux)"
            return "That \(statement) holds only where `core.ignorecase` is \(setting); "
                + "the other setting gives the opposite result."
        case .unchecked(let reason):
            return "Not checked: \(reason)."
        case .wrong(let slip):
            return [correction, slip.flatMap { Self.reasons[$0] }, fix.map(advice)].compactMap { $0 }
                .joined(separator: " ")
        }
    }

    /// The claim in words: "`logs/keep.log` is not ignored".
    var statement: String {
        switch claim.assertion {
        case .ignored: "`\(claim.subject)` is ignored"
        case .notIgnored: "`\(claim.subject)` is not ignored"
        case .anyDepth: "`\(claim.subject)` matches at any depth"
        case .topLevelOnly: "`\(claim.subject)` matches only at the top level"
        case .takesEffect: "`\(claim.subject)` works as a pattern"
        case .untracks: "A .gitignore entry untracks a file"
        case .keepsTracking: "A .gitignore entry leaves tracked files tracked"
        }
    }

    var confirmation: String {
        switch claim.kind {
        case .path: "Right: \(truth)."
        case .scope: "Right: \(statement)" + (example.map { " (`\($0)`)" } ?? "") + "."
        case .line, .tracking: "Right: \(statement)."
        }
    }

    /// What git actually does with the claim's path, and which line decides it.
    var truth: String {
        guard let verdict else { return statement }
        let path = "`\(claim.subject)`"
        guard let line = verdict.decidingPattern else { return "\(path) is not ignored: no line matches it" }
        if let parent = verdict.excludedParent {
            return "\(path) is ignored: `\(line.line)` excludes its directory `\(parent)`"
        }
        return line.isNegated ? "\(path) is not ignored: `\(line.line)` re-includes it"
            : "\(path) is ignored by `\(line.line)`"
    }

    var correction: String {
        switch claim.kind {
        case .path:
            return "\(truth), so the claim that it is \(claim.assertion == .ignored ? "ignored" : "kept") is wrong."
        case .scope:
            let shown = example.map { " (`\($0)` is \(claim.assertion == .anyDepth ? "not " : "")matched)" } ?? ""
            return claim.assertion == .anyDepth
                ? "`\(claim.subject)` does not match at any depth\(shown)."
                : "`\(claim.subject)` matches at every level, not only the top\(shown)."
        case .line:
            return "`\(claim.subject)` does not ignore " + (example.map { "`\($0)`." } ?? "what it was written for.")
        case .tracking:
            return "Adding a path to .gitignore does not untrack a file git already tracks."
        }
    }

    static let reasons: [Slip: String] = [
        .trailingComment:
            "git reads `#` as a comment only at the start of a line, so the comment is part of the pattern.",
        .reincludeUnderExcludedDirectory:
            "git cannot re-include a file inside an excluded directory, so the `!` line has no effect.",
        .directoryOnly: "A pattern ending in `/` matches only directories.",
        .slashAnchors: "A slash at the start or in the middle anchors a pattern to the directory of its .gitignore.",
        .slashlessMatchesEverywhere: "A pattern with no slash (other than a trailing one) matches at every level.",
        .starStopsAtSlash: "`*` does not match `/`; `**` does.",
        .doubleStarMatchesZero: "`/**/` matches zero or more directories.",
        .starMatchesDotfiles: "In .gitignore `*` also matches a leading dot.",
        .lastMatchWins: "When several lines match a path, the last one decides.",
        .alreadyTracked: "Ignore rules apply only to untracked files: a committed file stays tracked until "
            + "`git rm --cached <path>`, which keeps it on disk and in earlier commits.",
        .letterCase:
            "Matching ignores case only where `core.ignorecase` is true; this repository is set the other way."
    ]

    func advice(_ fix: String) -> String {
        switch outcome {
        case .wrong(.trailingComment?):
            "Put `\(fix)` on its own line and the comment on the line above."
        case .wrong(.reincludeUnderExcludedDirectory?):
            "Write `\(fix)` instead, so the directory stays open and the `!` line can work."
        default:
            "`\(fix)` does what the answer expects."
        }
    }
}
