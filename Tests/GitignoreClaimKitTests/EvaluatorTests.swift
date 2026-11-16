import Testing
@testable import GitignoreClaimKit

@Suite("Judging claims")
struct EvaluatorTests {
    @Test("Each slip", arguments: [
        (fenced("logs/\n!logs/keep.log") + "\nThis keeps `logs/keep.log` tracked.", IgnoreFinding.Slip.reincludeUnderExcludedDirectory),
        (fenced("*.log # logs") + "\nThis ignores `a.log`.", .trailingComment),
        ("`build/` ignores a file named `build`.", .directoryOnly),
        ("`doc/*.txt` matches `x/doc/a.txt`.", .slashAnchors),
        ("`*.log` doesn't match `x/a.log`.", .slashlessMatchesEverywhere),
        ("`doc/*.txt` matches `doc/a/b.txt`.", .starStopsAtSlash),
        ("`a/**/b` won't match `a/b`.", .doubleStarMatchesZero),
        ("`*.env` doesn't match `.env`.", .starMatchesDotfiles),
        (fenced("!keep.log\n*.log") + "\n`keep.log` is not ignored.", .lastMatchWins),
        ("Adding it to .gitignore will stop tracking it.", .alreadyTracked)
    ])
    func slips(_ text: String, _ expected: IgnoreFinding.Slip) {
        let finding = check(text).findings.first { $0.claim.isExplicit }
        #expect(slip(finding) == expected)
        #expect(finding?.explanation.isEmpty == false)
    }

    @Test("Fixes", arguments: [
        (fenced("logs/\n!logs/keep.log") + "\nThis keeps `logs/keep.log` tracked.", "logs/*"),
        (fenced("/logs/\n!/logs/keep.log") + "\nThis keeps `logs/keep.log` tracked.", "/logs/*"),
        (fenced("*.log # logs") + "\nThis ignores `a.log`.", "*.log"),
        ("`build/` ignores a file named `build`.", "build"),
        ("`doc/*.txt` matches `x/doc/a.txt`.", "**/doc/*.txt"),
        ("`build/` doesn't match `x/build/`.", "/build/"),
        ("`doc/*.txt` matches `doc/a/b.txt`.", "doc/**/*.txt")
    ])
    func fixes(_ text: String, _ expected: String) {
        #expect(check(text).findings.first { $0.claim.isExplicit }?.fix == expected)
    }

    @Test("No fix when the excluded directory is further up, or the slip has none")
    func noFix() {
        let deeper = fenced("logs/\n!logs/a/keep.log") + "\nThis keeps `logs/a/keep.log` tracked."
        #expect(check(deeper).findings.first?.fix == nil)
        #expect(Fixes.fix(for: nil, line: nil, verdict: IgnoreRules("").verdict(for: "a"), path: "a") == nil)
        let line = IgnorePattern(line: "a", lineNumber: 1, directory: "")
        #expect(Fixes.fix(for: .lastMatchWins, line: line, verdict: IgnoreRules("").verdict(for: "a"), path: "a") == nil)
        let nested = IgnorePattern(line: "logs/", lineNumber: 1, directory: "x/")
        let verdict = IgnoreVerdict(isIgnored: true, decidingPattern: nested, excludedParent: "x/logs/")
        #expect(Fixes.fix(for: .reincludeUnderExcludedDirectory, line: nested, verdict: verdict, path: "x/logs/a") == nil)
    }

    @Test("A wrong claim with no recognisable slip")
    func noSlip() {
        let finding = only("`a.txt` matches `b.txt`.")
        #expect(slip(finding) == nil && finding?.severity == .wrong)
        #expect(finding?.explanation.contains("no line matches") == true)
    }

    @Test("Letter case")
    func letterCase() {
        let answer = fenced("*.LOG") + "\n`app.log` is ignored."
        if case .caveat(.dependsOnIgnoreCase(let holdsWhen))? = only(answer)?.outcome {
            #expect(holdsWhen)
        } else {
            Issue.record("expected a caveat")
        }
        let opposite = fenced("*.LOG") + "\n`app.log` is not ignored."
        if case .caveat(.dependsOnIgnoreCase(let holdsWhen))? = only(opposite)?.outcome {
            #expect(!holdsWhen)
        } else {
            Issue.record("expected a caveat")
        }
        #expect(slip(only(answer, .caseSensitive)) == .letterCase)
        #expect(only(answer, .caseInsensitive)?.severity == .holds)
        #expect(only(answer, .lenient)?.severity == .holds)
        #expect(only(opposite)?.explanation.contains("false") == true)
    }

    @Test("Unchecked claims")
    func unchecked() {
        #expect(only(fenced("build/") + "\n`build` is ignored.")?.severity == .unchecked)
        let noRules = IgnoreClaim(kind: .path, subject: "a", assertion: .ignored, sentence: "")
        #expect(IgnoreClaimChecker().judge(noRules).severity == .unchecked)
        let noSample = IgnoreClaim(kind: .scope, subject: "[!a]x", assertion: .anyDepth, sentence: "")
        #expect(IgnoreClaimChecker().judge(noSample).severity == .unchecked)
        #expect(only("In `.dockerignore`, `*.log` matches `logs/a.log`.")?.explanation.hasPrefix("Not checked") == true)
    }

    @Test("Scope claims that hold and fail")
    func scope() {
        #expect(only("`/build` only matches at the root.")?.explanation
            == "Right: `/build` matches only at the top level (`sub/build`).")
        #expect(only("`/build` matches anywhere.")?.explanation.hasPrefix(
            "`/build` does not match at any depth (`sub/build` is not matched).") == true)
        #expect(only(fenced("*.log # logs"))?.explanation.hasPrefix("`*.log # logs` does not ignore `x.log`.") == true)
        #expect(only("`a/b` matches anywhere.")?.fix == "**/a/b")
        #expect(only("`*.log` only matches at the top level.")?.fix == "/*.log")
    }

    @Test("Samples", arguments: [
        ("**/a/**", "a/x"), ("[ab]c", "ac"), ("\\#x", "#x"), ("a?c", "axc"), ("/x", "x"), ("d/", "d/")
    ])
    func samples(_ line: String, _ expected: String) throws {
        let pattern = try #require(IgnorePattern(line: line, lineNumber: 1, directory: ""))
        #expect(Samples.path(for: pattern) == expected)
    }

    @Test("Patterns with no sample", arguments: ["[!a]x", "[abc", "[[:digit:]]x", "[]", "a\\"])
    func noSample(_ line: String) throws {
        let pattern = try #require(IgnorePattern(line: line, lineNumber: 1, directory: ""))
        #expect(Samples.path(for: pattern) == nil)
    }
}
