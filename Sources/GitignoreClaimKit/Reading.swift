/// A way of misreading .gitignore rules. Checking a wrong claim under each one names the mistake behind it:
/// if the claim holds once trailing comments are stripped, the answer took `# ...` for a comment.
struct Reading: OptionSet, Sendable, Hashable {
    let rawValue: Int

    /// `*.log  # logs` read as `*.log` plus a comment.
    static let trailingComments = Reading(rawValue: 1 << 0)
    /// A negated file re-included although its parent directory is excluded.
    static let parentExclusionIgnored = Reading(rawValue: 1 << 1)
    /// `build/` read as also matching a file named `build`.
    static let directoryOnlyMatchesFiles = Reading(rawValue: 1 << 2)
    /// `doc/*.txt` read as matching `x/doc/a.txt` too.
    static let anchoredMatchesAnywhere = Reading(rawValue: 1 << 3)
    /// `*.log` or `build/` read as matching only at the top level.
    static let slashlessIsRootOnly = Reading(rawValue: 1 << 4)
    /// `doc/*.txt` read as matching `doc/a/b.txt`.
    static let starCrossesSlash = Reading(rawValue: 1 << 5)
    /// `a/**/b` read as needing at least one directory between `a` and `b`.
    static let doubleStarNeedsDirectory = Reading(rawValue: 1 << 6)
    /// `*.env` read as not matching `.env`, the way a shell glob skips dotfiles.
    static let starSkipsDotfiles = Reading(rawValue: 1 << 7)
    /// The first matching line read as deciding, instead of the last.
    static let firstMatchWins = Reading(rawValue: 1 << 8)
}
