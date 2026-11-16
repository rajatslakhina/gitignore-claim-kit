/// Reads what an answer says about .gitignore rules and checks every claim with git's own matching rules: the
/// one call most callers need.
public struct IgnoreClaimChecker: Sendable {
    public let policy: IgnorePolicy
    public let reader: IgnoreClaimReader

    public init(policy: IgnorePolicy = .standard) {
        self.policy = policy
        reader = IgnoreClaimReader(checksLines: policy.checksLines)
    }

    public func claims(in text: String, context: String = "") -> [IgnoreClaim] {
        reader.claims(in: text, context: context)
    }

    public func judge(_ claim: IgnoreClaim) -> IgnoreFinding {
        IgnoreEvaluator(policy: policy).judge(claim)
    }

    /// Every claim's finding. A .gitignore line that works as written makes no finding of its own, so that an
    /// answer with a long .gitignore is not reported as a long list of claims that hold. `context` is other text
    /// from the conversation (the question, say): when it, or the answer, mentions an ignore file, a sentence's
    /// own patterns are read as ignore rules; otherwise "`[a-z]+` matches `abc`" is left alone.
    public func check(_ text: String, context: String = "") -> IgnoreReport {
        report(claims(in: text, context: context))
    }

    func report(_ claims: [IgnoreClaim]) -> IgnoreReport {
        IgnoreReport(findings: claims.map(judge).filter { $0.claim.isExplicit || $0.severity != .holds })
    }
}

/// Checks a conversation's answers one after another and remembers what it flagged, so a wrong claim stated
/// again after a correction was asked for is marked as repeated rather than new.
public actor IgnoreLedger {
    public struct Statistics: Sendable, Hashable {
        public var reviews = 0
        public var claims = 0
        public var flagged = 0
        public var repeated = 0
    }

    public nonisolated let checker: IgnoreClaimChecker
    public private(set) var statistics = Statistics()
    private var flaggedKeys: Set<String> = []
    /// Whether the last answer reviewed, or its context, mentioned an ignore file.
    public private(set) var isAboutIgnoreRules = false

    public init(checker: IgnoreClaimChecker = IgnoreClaimChecker()) {
        self.checker = checker
    }

    /// Checks one answer. `context` is the question it answers. A turn where neither mentions an ignore file
    /// makes no new claims from its sentences' own patterns ("`[a-z]+` matches `abc`" in a later question about
    /// regexes is about regexes); it keeps only those that repeat a claim flagged earlier in the conversation,
    /// so "you're right, `doc/*.txt` does match `doc/a/b.txt`" after a correction is still caught.
    public func review(_ text: String, context: String = "") -> IgnoreReport {
        isAboutIgnoreRules = IgnoreClaimReader.isAboutIgnoreRules(context) || IgnoreClaimReader.isAboutIgnoreRules(text)
        let all = checker.reader.claims(in: text, context: context, assumingIgnoreContext: true)
        let claims = isAboutIgnoreRules ? all : all.filter { !$0.restsOnSentence || flaggedKeys.contains($0.key) }
        var findings = checker.report(claims).findings
        var keys: Set<String> = []
        for index in findings.indices where findings[index].severity >= .caution {
            let key = findings[index].key
            findings[index].isRepeated = flaggedKeys.contains(key)
            keys.insert(key)
        }
        flaggedKeys.formUnion(keys)
        let report = IgnoreReport(findings: findings)
        statistics.reviews += 1
        statistics.claims += findings.count
        statistics.flagged += report.flagged.count
        statistics.repeated += report.repeatedCount
        return report
    }

    /// Starts a new conversation: nothing flagged so far counts as a repeat, and nothing is assumed about ignore
    /// files.
    public func forget() {
        flaggedKeys.removeAll()
        isAboutIgnoreRules = false
    }
}
