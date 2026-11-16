/// The ignore rules of a working tree: one or more .gitignore files, each applying to its own directory.
public struct IgnoreRules: Sendable, Hashable {
    /// The files, keyed by directory (`""` for the root, otherwise ending in `/`), as written.
    public let files: [String: String]

    /// A single .gitignore at the root of the repository.
    public init(_ gitignore: String) {
        files = ["": gitignore]
    }

    /// Several .gitignore files. A key such as `logs` or `logs/` places that file in `logs/`; two keys naming
    /// the same directory are joined in key order.
    public init(files: [String: String]) {
        var normalized: [String: String] = [:]
        for (key, text) in files.sorted(by: { $0.key < $1.key }) {
            normalized[Self.directoryKey(key), default: ""] += text
        }
        self.files = normalized
    }

    static func directoryKey(_ key: String) -> String {
        let trimmed = key.split(separator: "/").joined(separator: "/")
        return trimmed.isEmpty ? "" : trimmed + "/"
    }

    /// Every pattern line, in the order git consults them for a path below all of their directories:
    /// files in deeper directories first, and within a file the last line first.
    func patterns(reading: Reading = []) -> [IgnorePattern] {
        files.sorted { $0.key.count > $1.key.count || ($0.key.count == $1.key.count && $0.key < $1.key) }
            .flatMap { directory, text in
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            return lines.enumerated().compactMap { offset, line in
                IgnorePattern(line: String(line), lineNumber: offset + 1, directory: directory, reading: reading)
            }.reversed()
        }
    }

    /// Whether git ignores `path` (relative to the root; a trailing `/` marks a directory), and why.
    public func verdict(for path: String, ignoreCase: Bool = false) -> IgnoreVerdict {
        let (cleaned, isDirectory) = Self.normalize(path)
        return verdict(for: cleaned, isDirectory: isDirectory, ignoreCase: ignoreCase)
    }

    public func verdict(for path: String, isDirectory: Bool, ignoreCase: Bool = false) -> IgnoreVerdict {
        verdict(path, isDirectory: isDirectory, ignoreCase: ignoreCase, reading: [])
    }

    func verdict(_ path: String, isDirectory: Bool, ignoreCase: Bool, reading: Reading) -> IgnoreVerdict {
        let all = patterns(reading: reading)
        let components = path.split(separator: "/").map(String.init)
        if !reading.contains(.parentExclusionIgnored) {
            for depth in 1..<max(components.count, 1) {
                let parent = components.prefix(depth).joined(separator: "/")
                let usable = all.filter { $0.directory.count <= parent.count && parent.hasPrefix($0.directory) }
                if let hit = Self.decide(usable, parent, true, ignoreCase, reading), !hit.isNegated {
                    return IgnoreVerdict(isIgnored: true, decidingPattern: hit, excludedParent: parent + "/")
                }
            }
        }
        let usable = all.filter { $0.directory.count < path.count && path.hasPrefix($0.directory) }
        let hit = Self.decide(usable, path, isDirectory, ignoreCase, reading)
        return IgnoreVerdict(isIgnored: hit.map { !$0.isNegated } ?? false, decidingPattern: hit, excludedParent: nil)
    }

    static func decide(_ patterns: [IgnorePattern], _ path: String, _ isDirectory: Bool, _ ignoreCase: Bool,
                       _ reading: Reading) -> IgnorePattern? {
        let order = reading.contains(.firstMatchWins) ? patterns.reversed() : patterns
        return order.first { $0.matches(path, isDirectory: isDirectory, ignoreCase: ignoreCase, reading: reading) }
    }

    /// Strips `./` and a leading `/`; a trailing `/` marks a directory.
    static func normalize(_ path: String) -> (String, Bool) {
        var text = path
        while text.hasPrefix("./") { text.removeFirst(2) }
        while text.hasPrefix("/") { text.removeFirst() }
        let isDirectory = text.hasSuffix("/")
        while text.hasSuffix("/") { text.removeLast() }
        return (text, isDirectory)
    }
}

/// What git decides about one path.
public struct IgnoreVerdict: Sendable, Hashable {
    public let isIgnored: Bool
    /// The line that decided it: the last matching line, or the line that excludes a parent directory.
    public let decidingPattern: IgnorePattern?
    /// The excluded parent directory (ending in `/`) when that is what decided it; nothing below an excluded
    /// directory can be re-included.
    public let excludedParent: String?
}
