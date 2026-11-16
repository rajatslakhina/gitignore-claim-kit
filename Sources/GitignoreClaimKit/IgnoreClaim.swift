/// One thing an answer says about .gitignore rules.
public struct IgnoreClaim: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        /// A path is, or is not, ignored.
        case path
        /// A pattern matches at any depth, or only at the top of its directory.
        case scope
        /// A .gitignore line does what it was written to do (a pattern with a ` # comment` after it).
        case line
        /// Adding a path to .gitignore stops (or does not stop) git tracking it.
        case tracking
    }

    public enum Assertion: String, Sendable, Hashable, CaseIterable {
        case ignored
        case notIgnored
        case anyDepth
        case topLevelOnly
        case takesEffect
        case untracks
        case keepsTracking
    }

    /// Where the rules a claim is judged against come from.
    public enum Source: Sendable, Hashable {
        /// The answer's n-th ignore file (1-based).
        case block(Int)
        /// Patterns named in the sentence itself.
        case sentence([String])
        /// Another tool's ignore file, which git's rules do not decide.
        case foreign(String)
        /// Nothing to judge against: a tracking claim needs no rules.
        case none
    }

    public let kind: Kind
    /// The path, pattern or line the claim is about.
    public let subject: String
    public let assertion: Assertion
    /// The sentence (or .gitignore line) it was read from.
    public let sentence: String
    /// Stated in prose, rather than implied by a line of a .gitignore.
    public let isExplicit: Bool
    public let source: Source
    let rules: IgnoreRules?
    /// Whether the subject path is a directory; `nil` when the answer does not say.
    let isDirectory: Bool?

    /// The same claim, about another tool's ignore file.
    func foreign(_ name: String) -> IgnoreClaim {
        IgnoreClaim(kind: kind, subject: subject, assertion: assertion, sentence: sentence, isExplicit: isExplicit,
                    source: .foreign(name), rules: nil, isDirectory: isDirectory)
    }

    init(kind: Kind, subject: String, assertion: Assertion, sentence: String, isExplicit: Bool = true,
         source: Source = .none, rules: IgnoreRules? = nil, isDirectory: Bool? = nil) {
        self.kind = kind
        self.subject = subject
        self.assertion = assertion
        self.sentence = sentence
        self.isExplicit = isExplicit
        self.source = source
        self.rules = rules
        self.isDirectory = isDirectory
    }
}
