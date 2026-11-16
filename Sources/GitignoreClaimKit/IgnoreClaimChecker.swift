/// Reads what an answer says about .gitignore rules and checks every claim with git's own matching rules: the
/// one call most callers need.
public struct IgnoreClaimChecker: Sendable {
    public let policy: IgnorePolicy
    public let reader: IgnoreClaimReader

    public init(policy: IgnorePolicy = .standard) {
        self.policy = policy
        reader = IgnoreClaimReader(checksLines: policy.checksLines)
    }

    public func claims(in text: String) -> [IgnoreClaim] {
        reader.claims(in: text)
    }

    public func judge(_ claim: IgnoreClaim) -> IgnoreFinding {
        IgnoreEvaluator(policy: policy).judge(claim)
    }

    /// Every claim's finding. A .gitignore line that works as written makes no finding of its own, so that an
    /// answer with a long .gitignore is not reported as a long list of claims that hold.
    public func check(_ text: String) -> IgnoreReport {
        IgnoreReport(findings: claims(in: text).map(judge).filter { $0.claim.isExplicit || $0.severity != .holds })
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

    public init(checker: IgnoreClaimChecker = IgnoreClaimChecker()) {
        self.checker = checker
    }

    public func review(_ text: String) -> IgnoreReport {
        var findings = checker.check(text).findings
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

    /// Starts a new conversation: nothing flagged so far counts as a repeat.
    public func forget() {
        flaggedKeys.removeAll()
    }
}
