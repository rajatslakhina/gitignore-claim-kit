/// How claims are held.
public struct IgnorePolicy: Sendable, Hashable {
    /// Whether .gitignore lines count as claims of their own.
    public var checksLines: Bool
    /// The repository's `core.ignorecase`; `nil` when unknown, and a claim that holds only under one setting
    /// is then a caveat.
    public var ignoreCase: Bool?
    /// Whether caveats are reported (otherwise such claims hold).
    public var reportsCaveats: Bool

    public init(checksLines: Bool = true, ignoreCase: Bool? = nil, reportsCaveats: Bool = true) {
        self.checksLines = checksLines
        self.ignoreCase = ignoreCase
        self.reportsCaveats = reportsCaveats
    }

    /// Lines checked, `core.ignorecase` unknown, caveats reported.
    public static let standard = IgnorePolicy()

    /// Only what an answer says in prose; caveats let through.
    public static let lenient = IgnorePolicy(checksLines: false, reportsCaveats: false)

    /// A repository on a case-sensitive file system (Linux, CI), `core.ignorecase = false`.
    public static let caseSensitive = IgnorePolicy(ignoreCase: false)

    /// A repository created on macOS or Windows, `core.ignorecase = true`.
    public static let caseInsensitive = IgnorePolicy(ignoreCase: true)
}
