import Testing
@testable import GitignoreClaimKit

@Suite("Parity with git")
struct ParityTests {
    @Test("Every row git produced is reproduced")
    func everyRow() {
        var checked = 0
        for parity in parityCases {
            let rules = IgnoreRules(files: parity.files.mapValues { $0.joined(separator: "\n") + "\n" })
            for row in parity.rows {
                let verdict = rules.verdict(for: row.path, ignoreCase: parity.ignoreCase)
                #expect(verdict.isIgnored == row.ignored, "\(parity.files) \(row.path)")
                checked += 1
            }
        }
        #expect(checked > 200)
    }
}
