/// What a claim about ignore rules turned out to be once git's rules were applied.
public struct IgnoreFinding: Sendable, Hashable {
    public enum Outcome: Sendable, Hashable {
        case exact
        /// Holds, with something a reader should know.
        case caveat(Caveat)
        case wrong(Slip?)
        /// Could not be checked, and why.
        case unchecked(String)
    }

    public enum Caveat: Sendable, Hashable {
        /// Holds only on a repository with this `core.ignorecase` setting (`git init` turns it on for a
        /// case-insensitive file system, such as macOS and Windows by default).
        case dependsOnIgnoreCase(holdsWhen: Bool)
    }

    /// A recognisable mistake behind a wrong claim.
    public enum Slip: String, Sendable, Hashable, CaseIterable {
        /// `*.log  # logs` read as a pattern and a comment: `#` starts a comment only at the start of a line.
        case trailingComment
        /// `!logs/keep.log` after `logs/`: nothing below an excluded directory can be re-included.
        case reincludeUnderExcludedDirectory
        /// `build/` read as matching a file named `build`: a trailing slash matches only directories.
        case directoryOnly
        /// `doc/*.txt` read as matching at any depth: a slash anywhere but the end anchors a pattern.
        case slashAnchors
        /// `*.log` or `build/` read as top-level only: a pattern without a slash matches at every level.
        case slashlessMatchesEverywhere
        /// `doc/*.txt` read as matching `doc/a/b.txt`: `*` does not cross `/`.
        case starStopsAtSlash
        /// `a/**/b` read as needing a directory between: `/**/` matches zero or more.
        case doubleStarMatchesZero
        /// `*.env` read as skipping `.env`: in .gitignore `*` matches a leading dot.
        case starMatchesDotfiles
        /// An earlier line read as deciding: the last matching line wins.
        case lastMatchWins
        /// Letters read as matching without case on a repository where `core.ignorecase` is false, or the
        /// other way round.
        case letterCase
        /// A .gitignore entry read as untracking a file git already tracks.
        case alreadyTracked
    }

    public enum Severity: Int, Sendable, Hashable, Comparable {
        case holds
        case unchecked
        case caution
        case wrong

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let claim: IgnoreClaim
    public let outcome: Outcome
    /// git's decision on the claim's path (for a path claim).
    public let verdict: IgnoreVerdict?
    /// A path that shows the difference (for scope and line claims).
    public let example: String?
    /// A line that does what the claim expected, where there is an obvious one.
    public let fix: String?
    /// Flagged in an earlier review of the same conversation (set by `IgnoreLedger`).
    public internal(set) var isRepeated = false

    init(claim: IgnoreClaim, outcome: Outcome, verdict: IgnoreVerdict? = nil, example: String? = nil,
         fix: String? = nil) {
        self.claim = claim
        self.outcome = outcome
        self.verdict = verdict
        self.example = example
        self.fix = fix
    }

    public var severity: Severity {
        switch outcome {
        case .exact: .holds
        case .unchecked: .unchecked
        case .caveat: .caution
        case .wrong: .wrong
        }
    }

    /// Identifies the same claim across rewrites.
    var key: String {
        "\(claim.kind)|\(claim.subject)|\(claim.assertion)".lowercased()
    }
}
