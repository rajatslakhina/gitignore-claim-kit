/// An inline code span of a sentence, read as a pattern, a path, an ignore file's name, or something else.
struct Span: Equatable {
    enum Role: Equatable {
        case pattern
        case negation
        case path
        case ignoreFile
        case other
    }

    let text: String
    let role: Role
    /// The prose just before it, lowercased: says "folder", "file", "unlike", ...
    let lead: String
    /// The prose just after it, lowercased.
    let tail: String

    /// The span as a path: `./` and a leading `/` dropped, a trailing `/` kept.
    var path: String {
        var text = self.text
        while text.hasPrefix("./") { text.removeFirst(2) }
        while text.hasPrefix("/") { text.removeFirst() }
        return text
    }

    /// Whether the prose around it says it is a directory (`true`) or a file (`false`).
    var isDirectoryHint: Bool? {
        if text.hasSuffix("/") { return true }
        let near: [String] = Array(Clauses.words(lead).suffix(3)) + Array(Clauses.words(tail).prefix(1))
        if near.contains(where: { ["folder", "directory", "dir", "folders", "directories"].contains($0) }) {
            return true
        }
        return near.contains { ["file", "files"].contains($0) } ? false : nil
    }

    /// Named as a container ("the contents of `logs/`", "everything in `logs/`"): the claim is about what is
    /// inside it, not about the directory.
    var isContainer: Bool {
        let words = Clauses.words(lead)
        guard let last = words.last else { return false }
        if ["inside", "within", "under", "beneath", "below", "contents"].contains(last) { return true }
        let holders = ["everything", "anything", "nothing", "files", "file", "contents", "content", "all", "entries",
                       "items", "whatever", "subfolders", "subdirectories", "folders", "directories", "else"]
        return ["in", "of"].contains(last) && words.dropLast().last.map(holders.contains) == true
    }

    /// Named as an exception: "everything is ignored except `logs/.gitkeep`".
    var isException: Bool {
        let words = Clauses.words(lead)
        let last2 = words.suffix(2).joined(separator: " ")
        return ["except", "besides", "excluding"].contains(words.last ?? "")
            || ["apart from", "other than", "but not", "except for"].contains(last2)
    }

    /// Introduced as the thing not chosen: "unlike `logs/`", "rather than `logs/`", "not `logs/`".
    var isContrasted: Bool {
        let markers = ["unlike", "rather than", "instead of", "than", "vs.", "vs", "versus", "as opposed to", "not",
                       "over", "replace", "replacing", "without"]
        let words = lead.trimmed.split(separator: " ").suffix(3).joined(separator: " ")
        return markers.contains { words == $0 || words.hasSuffix(" " + $0) }
    }

    static func role(of text: String, blockLines: Set<String>) -> Role {
        let folded = text.folded
        if folded.hasSuffix("ignore") && (folded.hasPrefix(".") || folded.contains("/.")) || folded.contains("ignore_")
            || folded.hasSuffix("info/exclude") {
            return .ignoreFile
        }
        if text.hasPrefix("!"), text.count > 1, !text.contains(" ") { return .negation }
        if blockLines.contains(text) { return .pattern }
        if let cut = IgnorePattern.trailingComment(in: text), !text[..<cut].contains(" "), cut > text.startIndex {
            return .pattern
        }
        if text.contains(" ") || text.isEmpty || text.hasPrefix("-") || text.contains("://") { return .other }
        if text.contains(where: { "*?[".contains($0) }) { return .pattern }
        let allowed = text.allSatisfy { $0.isLetter || $0.isNumber || "._-/~@+#".contains($0) }
        guard allowed, text.contains(where: { $0.isLetter || $0.isNumber }) else { return .other }
        return text.hasPrefix("/") && text.count > 1 && !text.dropFirst().contains("/") ? .pattern : .path
    }

    /// The code spans of a clause, with the prose around each.
    static func read(_ pieces: [(text: String, isCode: Bool)], blockLines: Set<String>) -> [Span] {
        pieces.indices.compactMap { index in
            guard pieces[index].isCode else { return nil }
            let lead = index > 0 ? pieces[index - 1].text.folded : ""
            let tail = index + 1 < pieces.count ? pieces[index + 1].text.folded : ""
            let text = pieces[index].text.trimmed
            return Span(text: text, role: role(of: text, blockLines: blockLines), lead: lead, tail: tail)
        }
    }
}
