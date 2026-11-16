/// One line of a .gitignore, read the way git reads it (`dir.c`): `#` starts a comment only at the start
/// of a line, unescaped trailing spaces are dropped, `!` negates, one trailing `/` restricts the line to
/// directories, and a `/` anywhere else anchors it to the directory of the file it is in.
public struct IgnorePattern: Sendable, Hashable {
    /// The line as written, without its line ending.
    public let line: String
    /// 1-based line number in its file.
    public let lineNumber: Int
    /// The directory of the .gitignore it comes from: `""` for the root, otherwise ending in `/`.
    public let directory: String
    public let isNegated: Bool
    public let isDirectoryOnly: Bool
    /// The pattern with `!` and the trailing `/` removed.
    let body: String
    /// Matched against the whole path below `directory` rather than its last component.
    let isAnchored: Bool

    /// `nil` for a blank line, a comment, or a line that is empty once trailing spaces are dropped.
    init?(line raw: String, lineNumber: Int, directory: String, reading: Reading = []) {
        var line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
        if reading.contains(.trailingComments), let cut = Self.trailingComment(in: line) {
            line = String(line[..<cut])
        }
        var text = Self.trimmingTrailingSpaces(line)
        let negated = text.hasPrefix("!")
        if negated { text.removeFirst() }
        let directoryOnly = text.hasSuffix("/")
        if directoryOnly { text.removeLast() }
        guard !text.isEmpty else { return nil }
        self.line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        self.lineNumber = lineNumber
        self.directory = directory
        isNegated = negated
        isDirectoryOnly = directoryOnly
        body = text
        isAnchored = text.contains("/")
    }

    /// Where a ` # comment` starts on a pattern line (whitespace, then an unescaped `#`), if it has one.
    static func trailingComment(in line: String) -> String.Index? {
        var previous: Character?
        var escaped = false
        for index in line.indices {
            let character = line[index]
            if character == "#", !escaped, let before = previous, before == " " || before == "\t" {
                var start = index
                while start > line.startIndex, " \t".contains(line[line.index(before: start)]) {
                    start = line.index(before: start)
                }
                return start
            }
            escaped = character == "\\" && !escaped
            previous = character
        }
        return nil
    }

    /// The line up to its ` # comment`, if it has one.
    static func withoutTrailingComment(_ line: String) -> String {
        guard let cut = trailingComment(in: line) else { return line }
        return String(line[..<cut])
    }

    /// git's `trim_trailing_spaces`: drops trailing spaces (not tabs) unless the first of them is escaped.
    static func trimmingTrailingSpaces(_ line: String) -> String {
        var cut: String.Index?
        var index = line.startIndex
        while index < line.endIndex {
            switch line[index] {
            case " ":
                if cut == nil { cut = index }
            case "\\":
                cut = nil
                index = line.index(after: index)
                if index == line.endIndex { return line }
            default:
                cut = nil
            }
            index = line.index(after: index)
        }
        return cut.map { String(line[..<$0]) } ?? line
    }

    /// Whether this line matches `path` (relative to the repository root, no trailing slash).
    func matches(_ path: String, isDirectory: Bool, ignoreCase: Bool, reading: Reading = []) -> Bool {
        if isDirectoryOnly, !isDirectory, !reading.contains(.directoryOnlyMatchesFiles) { return false }
        let flags: Wildmatch.Flags = ignoreCase ? [.caseFold] : []
        guard isAnchored || reading.contains(.slashlessIsRootOnly) else {
            let name = path.lastIndex(of: "/").map { String(path[path.index(after: $0)...]) } ?? path
            if reading.contains(.starSkipsDotfiles), name.hasPrefix("."), body.first.map("*?[".contains) == true {
                return false
            }
            return Wildmatch.matches(body, name, flags: flags)
        }
        guard let name = Self.below(directory, path, ignoreCase) else { return false }
        var pattern = Self.unrooted(body)
        if reading.contains(.anchoredMatchesAnywhere), isAnchored, !pattern.hasPrefix("**/") {
            pattern = "**/" + pattern
        }
        if reading.contains(.doubleStarNeedsDirectory) {
            pattern = pattern.replacingOccurrences(of: "/**/", with: "/*/**/")
            if pattern.hasPrefix("**/") { pattern = "*/" + pattern }
        }
        return Wildmatch.matches(pattern, name, flags: reading.contains(.starCrossesSlash) ? flags
                                 : flags.union(.pathname))
    }

    /// The part of `path` below `directory`, or `nil` when the path is not inside it.
    static func below(_ directory: String, _ path: String, _ ignoreCase: Bool) -> String? {
        guard !directory.isEmpty else { return path }
        let head = String(path.prefix(directory.count))
        let same = ignoreCase ? head.lowercased() == directory.lowercased() : head == directory
        return same && path.count > directory.count ? String(path.dropFirst(directory.count)) : nil
    }

    static func unrooted(_ body: String) -> String {
        body.hasPrefix("/") ? String(body.dropFirst()) : body
    }
}
