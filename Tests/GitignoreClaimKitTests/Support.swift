@testable import GitignoreClaimKit

/// The context most tests run in: a question about .gitignore.
let gitignoreQuestion = "How should I write my .gitignore?"

/// The report for an answer under a policy, in a conversation about .gitignore.
func check(_ text: String, _ policy: IgnorePolicy = .standard) -> IgnoreReport {
    IgnoreClaimChecker(policy: policy).check(text, context: gitignoreQuestion)
}

/// The single finding an answer produces (fails the caller's expectation by returning nil otherwise).
func only(_ text: String, _ policy: IgnorePolicy = .standard) -> IgnoreFinding? {
    let findings = check(text, policy).findings
    return findings.count == 1 ? findings[0] : nil
}

func slip(_ finding: IgnoreFinding?) -> IgnoreFinding.Slip? {
    if case .wrong(let slip)? = finding?.outcome { return slip }
    return nil
}

func claims(_ text: String) -> [IgnoreClaim] {
    IgnoreClaimReader().claims(in: text, assumingIgnoreContext: true)
}

func fenced(_ lines: String, tag: String = "gitignore") -> String {
    "```\(tag)\n\(lines)\n```"
}
