import GitignoreClaimKit

/// Prints a heading for a scenario.
func scenario(_ number: Int, _ title: String) {
    print("")
    print("== \(number). \(title)")
}

/// Prints an answer's report: its verdict, a summary line and one line per finding.
func show(_ label: String, _ report: IgnoreReport) {
    print("-- \(label): \(report.verdict.rawValue) (\(report.summary))")
    for finding in report.findings {
        let mark = switch finding.severity {
        case .holds: "ok   "
        case .unchecked: "skip "
        case .caution: "check"
        case .wrong: "WRONG"
        }
        let repeated = finding.isRepeated ? " [repeated]" : ""
        print("   \(mark) \(finding.claim.kind.rawValue): \(finding.explanation)\(repeated)")
    }
}

/// Prints one line of git's verdict for a path.
func explain(_ rules: IgnoreRules, _ path: String) {
    let verdict = rules.verdict(for: path)
    let line = verdict.decidingPattern.map { " <- `\($0.line)` (line \($0.lineNumber))" } ?? ""
    let parent = verdict.excludedParent.map { " via excluded \($0)" } ?? ""
    print("   \(verdict.isIgnored ? "ignored" : "kept   ")  \(path)\(line)\(parent)")
}
