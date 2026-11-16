import Testing
@testable import GitignoreClaimKit

@Suite("Reports and the ledger")
struct ReportTests {
    @Test("Verdicts")
    func verdicts() {
        #expect(check("Nothing here.").verdict == .noClaims)
        #expect(check("`*.log` matches `x/a.log`.").verdict == .verified)
        #expect(check(fenced("build/") + "\n`build` is ignored.").verdict == .unchecked)
        #expect(check(fenced("*.LOG") + "\n`a.log` is ignored.").verdict == .caution)
        #expect(check("`*.log` matches `a.txt`.").verdict == .wrong)
    }

    @Test("Notes, feedback and summaries")
    func text() {
        let right = check("`*.log` matches `x/a.log`.")
        #expect(right.note == nil && right.feedback == nil && right.corrections.isEmpty)
        #expect(right.summary == "1 claim checked, 1 hold")
        #expect(check("Nothing.").summary == "no claims about ignore rules")
        let mixed = check(fenced("*.LOG\nbuild/") + "\n`a.log` is ignored, `build` is ignored, `b.txt` is ignored"
            + " and `c.LOG` is ignored.")
        #expect(mixed.summary == "4 claims checked, 1 hold, 1 unchecked, 1 to check, 1 wrong")
        #expect(mixed.note?.hasPrefix("Gitignore check: ") == true)
        #expect(mixed.feedback?.contains("git check-ignore -v --no-index") == true)
    }

    @Test("Explanations of claims that hold")
    func confirmations() {
        let claim = IgnoreClaim(kind: .tracking, subject: "x", assertion: .keepsTracking, sentence: "")
        #expect(IgnoreClaimChecker().judge(claim).explanation == "Right: A .gitignore entry leaves tracked files tracked.")
        let line = IgnoreFinding(claim: IgnoreClaim(kind: .line, subject: "a", assertion: .takesEffect, sentence: ""),
                                 outcome: .exact)
        #expect(line.explanation == "Right: `a` works as a pattern.")
        #expect(line.truth == "`a` works as a pattern")
        let noExample = IgnoreFinding(claim: IgnoreClaim(kind: .line, subject: "a # b", assertion: .takesEffect,
                                                         sentence: ""), outcome: .wrong(nil))
        #expect(noExample.explanation == "`a # b` does not ignore what it was written for.")
        let scope = IgnoreFinding(claim: IgnoreClaim(kind: .scope, subject: "a", assertion: .anyDepth, sentence: ""),
                                  outcome: .wrong(nil))
        #expect(scope.explanation == "`a` does not match at any depth.")
        let untracks = IgnoreFinding(claim: IgnoreClaim(kind: .tracking, subject: "x", assertion: .untracks,
                                                        sentence: ""), outcome: .exact)
        #expect(untracks.statement == "A .gitignore entry untracks a file")
        let top = IgnoreFinding(claim: IgnoreClaim(kind: .scope, subject: "a", assertion: .topLevelOnly, sentence: ""),
                                outcome: .exact)
        #expect(top.explanation == "Right: `a` matches only at the top level.")
    }

    @Test("Every slip has a reason")
    func reasons() {
        for slip in IgnoreFinding.Slip.allCases {
            #expect(IgnoreFinding.reasons[slip]?.isEmpty == false)
        }
        #expect(IgnoreFinding.Severity.holds < .wrong)
    }

    @Test("The ledger marks a claim repeated after a correction")
    func ledger() async {
        let ledger = IgnoreLedger()
        let first = await ledger.review("`*.log` doesn't match `x/a.log`.", context: gitignoreQuestion)
        #expect(first.repeatedCount == 0 && first.verdict == .wrong)
        let second = await ledger.review("Again, `*.log` doesn't match `x/a.log`.")
        #expect(second.repeatedCount == 1)
        #expect(second.note?.contains("stated again") == true)
        #expect(second.summary.hasSuffix("1 repeated"))
        #expect(await !ledger.isAboutIgnoreRules)
        let unrelated = await ledger.review("`[a-z]+` matches `abc`.", context: "What does this regex match?")
        #expect(unrelated.verdict == .noClaims)
        _ = await ledger.review("Fine.", context: "Back to my .gitignore.")
        #expect(await ledger.isAboutIgnoreRules)
        await ledger.forget()
        #expect(await !ledger.isAboutIgnoreRules)
        let third = await ledger.review("`*.log` doesn't match `x/a.log`.")
        #expect(third.verdict == .noClaims)
        let fourth = await ledger.review("In a .gitignore, `*.log` doesn't match `x/a.log`.")
        #expect(fourth.repeatedCount == 0 && fourth.verdict == .wrong)
        let stats = await ledger.statistics
        #expect(stats.reviews == 6 && stats.claims == 3 && stats.flagged == 3 && stats.repeated == 1)
        #expect(ledger.checker.policy == .standard)
        #expect(IgnoreClaimChecker().claims(in: "`*.log` matches `a.log`.", context: gitignoreQuestion).count == 1)
    }
}
