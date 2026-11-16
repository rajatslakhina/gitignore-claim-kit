import Testing
@testable import GitignoreClaimKit

@Suite("README examples")
struct ReadmeTests {
    @Test("The usage example returns what the README says")
    func usage() throws {
        let answer = "Add this to your `.gitignore`:\n\n```gitignore\nlogs/\n!logs/keep.log\n```\n\n"
            + "This ignores everything in `logs/` but keeps `logs/keep.log` tracked."
        let report = IgnoreClaimChecker().check(answer)
        #expect(report.verdict == .wrong)
        #expect(report.summary == "1 claim checked, 0 hold, 1 wrong")
        #expect(report.note?.hasPrefix("Gitignore check: `logs/keep.log` is ignored: `logs/` excludes its directory")
            == true)
        #expect(report.feedback != nil)
        #expect(report.findings.first?.fix == "logs/*")
        let rules = IgnoreRules("logs/*\n!logs/keep.log\n")
        #expect(!rules.verdict(for: "logs/keep.log").isIgnored)
        #expect(rules.verdict(for: "logs/app.log").decidingPattern?.line == "logs/*")
        let checker = IgnoreClaimChecker()
        #expect(checker.check("`doc/*.txt` matches `doc/server/arch.txt`.").verdict == .noClaims)
        #expect(checker.check("`doc/*.txt` matches `doc/server/arch.txt`.",
                              context: "How do I set up my .gitignore?").verdict == .wrong)
        let nested = IgnoreRules(files: ["": "*.tmp\n", "logs/": "*\n!.gitignore\n"])
        #expect(!nested.verdict(for: "logs/.gitignore").isIgnored)
    }
}
