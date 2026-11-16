import Testing
@testable import GitignoreClaimKit

@Suite("wildmatch")
struct WildmatchTests {
    @Test("Escapes, ? and stars", arguments: [
        ("abc\\", "abc", false), ("abc\\", "abcd", false), ("\\*x", "*x", true),
        ("a?c", "abc", true), ("foo**bar", "foo/bar", false), ("foo**bar", "fooxbar", true),
        ("a/**\\/b", "a/x/b", true), ("*/x", "abc", false), ("a/*", "a/b/c", false), ("a/*", "a/b", true),
        ("**/a*b/c", "x/ab/c", true), ("**/a*b/c", "x/ab/d", false), ("a*b", "a/xb", false),
        ("*b", "a/b", false), ("**", "a/b", true), ("a/**", "a/b/c", true), ("*x*", "a/x", false),
        ("*[ab]", "x/a", false)
    ])
    func pathname(_ pattern: String, _ text: String, _ expected: Bool) {
        #expect(Wildmatch.matches(pattern, text, flags: .pathname) == expected)
    }

    @Test("Without pathname, a star crosses slashes")
    func noPathname() {
        #expect(Wildmatch.matches("a*b", "a/xb", flags: []))
        #expect(Wildmatch.matches("a**b", "a/x/b", flags: []))
        #expect(Wildmatch.matches("a/*/b", "a/x/y/b", flags: []))
        #expect(!Wildmatch.matches("a*q", "a/xb", flags: []))
        #expect(!Wildmatch.matches("*[ab]", "xyz", flags: []))
    }

    @Test("Brackets", arguments: [
        ("[\\]]", "]", true), ("[\\", "x", false), ("[a-\\z]", "m", true), ("[abc", "a", false),
        ("[[:x]", ":", true), ("[[:x]", "x", true), ("[[:foo:]]", "a", false), ("[[:alpha", "a", false),
        ("a[/]b", "a/b", false), ("[[:]", ":", true), ("[!a]", "b", true), ("[^a]", "a", false),
        ("[a-]", "-", true), ("[b-a]", "a", false)
    ])
    func brackets(_ pattern: String, _ text: String, _ expected: Bool) {
        #expect(Wildmatch.matches(pattern, text, flags: .pathname) == expected)
    }

    @Test("Named classes", arguments: [
        ("alnum", "a", true), ("alnum", "-", false), ("alpha", "Z", true), ("blank", " ", true),
        ("blank", "\t", true), ("blank", "a", false), ("cntrl", "\u{1}", true), ("cntrl", "a", false),
        ("cntrl", "\u{7f}", true), ("digit", "7", true), ("graph", "~", true), ("graph", " ", false),
        ("lower", "a", true), ("lower", "A", false), ("print", " ", true), ("punct", "!", true),
        ("punct", "a", false), ("space", "\n", true), ("upper", "A", true), ("upper", "a", false),
        ("xdigit", "f", true), ("xdigit", "F", true), ("xdigit", "g", false)
    ])
    func named(_ name: String, _ text: String, _ expected: Bool) {
        #expect(Wildmatch.matches("[[:\(name):]]", text, flags: []) == expected)
    }

    @Test("Case folding")
    func caseFold() {
        #expect(Wildmatch.matches("*.LOG", "app.log", flags: .caseFold))
        #expect(Wildmatch.matches("[A-C]x", "bx", flags: .caseFold))
        #expect(Wildmatch.matches("[[:upper:]]", "a", flags: .caseFold))
        #expect(!Wildmatch.matches("[B]", "b", flags: .caseFold))
        #expect(!Wildmatch.matches("\\Z", "z", flags: .caseFold))
        #expect(Wildmatch.matches("A*Q", "axyq", flags: .caseFold))
    }
}

@Suite("Lines and rules")
struct RulesTests {
    @Test("Lines git does not read as patterns")
    func skipped() {
        #expect(IgnorePattern(line: "", lineNumber: 1, directory: "") == nil)
        #expect(IgnorePattern(line: "# comment", lineNumber: 1, directory: "") == nil)
        #expect(IgnorePattern(line: "   ", lineNumber: 1, directory: "") == nil)
        #expect(IgnorePattern(line: "!", lineNumber: 1, directory: "") == nil)
        #expect(IgnorePattern(line: "/", lineNumber: 1, directory: "") == nil)
    }

    @Test("Line endings, escapes and trailing spaces")
    func parsing() throws {
        let crlf = try #require(IgnorePattern(line: "build/\r", lineNumber: 3, directory: ""))
        #expect(crlf.line == "build/" && crlf.isDirectoryOnly && crlf.lineNumber == 3)
        #expect(IgnorePattern.trimmingTrailingSpaces("a\\") == "a\\")
        #expect(IgnorePattern.trimmingTrailingSpaces("a\\  ") == "a\\ ")
        #expect(IgnorePattern.trimmingTrailingSpaces("a \t") == "a \t")
        #expect(IgnorePattern.trailingComment(in: "a \\#b") == nil)
        #expect(IgnorePattern.trailingComment(in: "a\t# b") != nil)
        #expect(IgnorePattern.trailingComment(in: "a#b") == nil)
        let stripped = try #require(IgnorePattern(line: "*.log  # logs", lineNumber: 1, directory: "",
                                                  reading: .trailingComments))
        #expect(stripped.matches("a.log", isDirectory: false, ignoreCase: false))
    }

    @Test("Paths below a nested .gitignore")
    func below() {
        #expect(IgnorePattern.below("sub/", "sub/x", false) == "x")
        #expect(IgnorePattern.below("sub/", "SUB/x", true) == "x")
        #expect(IgnorePattern.below("sub/", "sub", false) == nil)
        #expect(IgnorePattern.below("sub/", "other/x", false) == nil)
    }

    @Test("Verdicts, normalised paths and merged files")
    func verdicts() {
        let rules = IgnoreRules(files: ["logs": "*\n", "logs/": "!keep\n", "": "*.tmp\n"])
        #expect(rules.files.count == 2)
        #expect(!rules.verdict(for: "./logs/keep").isIgnored)
        #expect(rules.verdict(for: "/logs/other").isIgnored)
        #expect(rules.verdict(for: "a.tmp/").isIgnored)
        let parent = IgnoreRules("logs/\n!logs/keep.log\n").verdict(for: "logs/keep.log")
        #expect(parent.isIgnored && parent.excludedParent == "logs/" && parent.decidingPattern?.lineNumber == 1)
        let none = IgnoreRules("*.log\n").verdict(for: "a.txt", isDirectory: false)
        #expect(!none.isIgnored && none.decidingPattern == nil && none.excludedParent == nil)
        #expect(IgnoreRules.directoryKey("/a//b/") == "a/b/")
        #expect(IgnoreRules.directoryKey("") == "")
        let siblings = IgnoreRules(files: ["cd": "!x\n", "ab": "x\n", "": "*\n"])
        #expect(siblings.patterns().map(\.directory) == ["ab/", "cd/", ""])
    }

    @Test("Misreadings", arguments: [
        ("logs/\n!logs/keep.log\n", "logs/keep.log", false, Reading.parentExclusionIgnored, false),
        ("build/\n", "build", false, .directoryOnlyMatchesFiles, true),
        ("doc/*.txt\n", "x/doc/a.txt", false, .anchoredMatchesAnywhere, true),
        ("**/doc/*.txt\n", "x/doc/a.txt", false, .anchoredMatchesAnywhere, true),
        ("*.log\n", "x/a.log", false, .slashlessIsRootOnly, false),
        ("doc/*.txt\n", "doc/a/b.txt", false, .starCrossesSlash, true),
        ("a/**/b\n", "a/b", false, .doubleStarNeedsDirectory, false),
        ("**/b\n", "b", false, .doubleStarNeedsDirectory, false),
        ("*.env\n", ".env", false, .starSkipsDotfiles, false),
        ("!keep.log\n*.log\n", "keep.log", false, .firstMatchWins, false),
        ("*.log # logs\n", "a.log", false, .trailingComments, true)
    ])
    func misreadings(_ text: String, _ path: String, _ isDirectory: Bool, _ reading: Reading, _ expected: Bool) {
        let rules = IgnoreRules(text)
        #expect(rules.verdict(path, isDirectory: isDirectory, ignoreCase: false, reading: reading).isIgnored == expected)
    }
}
