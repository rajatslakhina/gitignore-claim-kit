/// An ignore file an answer shows in a fenced code block.
struct RuleBlock: Equatable {
    enum Kind: Equatable {
        /// A .gitignore whose patterns apply to `directory` (`""` for the root, otherwise ending in `/`).
        case gitignore(directory: String)
        /// Another tool's ignore file (`.dockerignore`, `.npmignore`, ...), which git's rules do not decide.
        case foreign(String)
    }

    let kind: Kind
    let lines: [String]
    /// Position among the answer's blocks of all kinds, prose included.
    let position: Int
    /// 1-based among the answer's ignore files.
    let number: Int
    /// Introduced as what not to do ("this does not work:"), so its lines are not held to their intent.
    let isCounterexample: Bool

    var text: String { lines.joined(separator: "\n") + "\n" }
}

enum RuleBlocks {
    static let gitTags: Set = ["gitignore", ".gitignore", "ignore", "git-ignore"]
    static let plainTags: Set = ["", "text", "txt", "plaintext", "plain", "git", "conf", "ini", "bash", "sh", "shell"]
    static let foreignFiles = [".dockerignore", ".npmignore", ".eslintignore", ".prettierignore", ".helmignore",
                               ".gcloudignore", ".vscodeignore", ".slugignore", ".cfignore", ".stylelintignore"]
    static let counterexampleMarkers = ["doesn't work", "does not work", "won't work", "will not work", "wrong",
                                        "incorrect", "broken", "instead of", "not this", "avoid", "don't do",
                                        "do not do", "bad:", "before:", "mistake", "common error"]

    /// Every ignore file shown in the answer, in order.
    static func find(in blocks: [AnswerBlock]) -> [RuleBlock] {
        var found: [RuleBlock] = []
        for (position, block) in blocks.enumerated() {
            guard case .code(let tag) = block.kind else { continue }
            let lead = position > 0 && blocks[position - 1].kind == .prose
                ? blocks[position - 1].lines.suffix(3).joined(separator: " ").folded : ""
            guard let kind = kind(tag: tag, lines: block.lines, lead: lead) else { continue }
            let counter = Words.containsAny(lead.suffix(160).description, counterexampleMarkers)
            found.append(RuleBlock(kind: kind, lines: block.lines, position: position, number: found.count + 1,
                                   isCounterexample: counter))
        }
        return found
    }

    static func kind(tag: String, lines: [String], lead: String) -> RuleBlock.Kind? {
        let header = lines.first?.trimmed.folded ?? ""
        let named = header.hasPrefix("#") ? header : ""
        if tag == "dockerignore" { return .foreign(".dockerignore") }
        if let foreign = foreignFiles.first(where: { named.contains($0) }) { return .foreign(foreign) }
        if named.contains(".gitignore") { return .gitignore(directory: directory(in: named)) }
        if gitTags.contains(tag) {
            return .gitignore(directory: directory(in: lead.contains(".gitignore") ? lead : ""))
        }
        guard plainTags.contains(tag), looksLikePatterns(lines) else { return nil }
        if let foreign = foreignFiles.first(where: { lead.contains($0) }) { return .foreign(foreign) }
        return lead.contains(".gitignore") ? .gitignore(directory: directory(in: lead)) : nil
    }

    /// `logs/.gitignore` names the directory `logs/`; a bare `.gitignore` is the root.
    static func directory(in text: String) -> String {
        guard let range = text.range(of: "/.gitignore") else { return "" }
        let before = text[..<range.lowerBound]
        let start = before.lastIndex { " `'\"(:".contains($0) }.map { before.index(after: $0) } ?? before.startIndex
        let path = String(before[start...])
        return path.hasPrefix("~") || path.hasPrefix(".git") ? "" : IgnoreRules.directoryKey(path)
    }

    /// Whether every line could be a .gitignore line rather than a command or code.
    static func looksLikePatterns(_ lines: [String]) -> Bool {
        let content = lines.map(\.trimmed).filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let commands = ["$", ">", "git ", "echo ", "cat ", "cd ", "touch ", "mkdir ", "npm ", "rm ", "printf "]
        return !content.isEmpty && !content.contains { line in
            commands.contains { line.hasPrefix($0) } || line.contains("=") || line.hasSuffix(";") || line.hasSuffix("{")
        }
    }
}
