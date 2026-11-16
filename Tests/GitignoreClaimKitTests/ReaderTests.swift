import Testing
@testable import GitignoreClaimKit

@Suite("Finding ignore files in an answer")
struct BlockTests {
    func kinds(_ text: String) -> [RuleBlock.Kind] {
        RuleBlocks.find(in: AnswerBlocks.split(text)).map(\.kind)
    }

    @Test("Tags, headers and the sentence before a block")
    func kinds() {
        #expect(kinds(fenced("*.log")) == [.gitignore(directory: "")])
        #expect(kinds(fenced("*.log", tag: "dockerignore")) == [.foreign(".dockerignore")])
        #expect(kinds(fenced("# .npmignore\n*.log", tag: "")) == [.foreign(".npmignore")])
        #expect(kinds(fenced("# logs/.gitignore\n*", tag: "text")) == [.gitignore(directory: "logs/")])
        #expect(kinds("Put this in `logs/.gitignore`:\n" + fenced("*")) == [.gitignore(directory: "logs/")])
        #expect(kinds("Add to `.gitignore`:\n" + fenced("build/", tag: "")) == [.gitignore(directory: "")])
        #expect(kinds("Add to `.dockerignore`:\n" + fenced("build/", tag: "")) == [.foreign(".dockerignore")])
        #expect(kinds("Some config:\n" + fenced("build/", tag: "")).isEmpty)
        #expect(kinds("Add to `.gitignore`:\n" + fenced("git add .", tag: "")).isEmpty)
        #expect(kinds("Add to `.gitignore`:\n" + fenced("# only a comment", tag: "")).isEmpty)
        #expect(kinds("Add to `.gitignore`:\n" + fenced("let x = 1", tag: "swift")).isEmpty)
        #expect(kinds("Add to `.gitignore`:\n" + fenced("a=1", tag: "")).isEmpty)
        #expect(kinds("Add to `.gitignore`:\n" + fenced("func a() {", tag: "")).isEmpty)
        #expect(kinds("```gitignore\n```") == [.gitignore(directory: "")])
        #expect(Words.contains("files stay untracked, untrack", "untrack"))
        #expect(!Words.contains("files stay untracked", "untrack"))
    }

    @Test("Directories named by the sentence before a block")
    func directories() {
        #expect(RuleBlocks.directory(in: "add to `logs/.gitignore`") == "logs/")
        #expect(RuleBlocks.directory(in: "add to ~/.gitignore") == "")
        #expect(RuleBlocks.directory(in: "or .git/.gitignore") == "")
        #expect(RuleBlocks.directory(in: "add to .gitignore") == "")
        #expect(RuleBlocks.directory(in: "a/b/.gitignore") == "a/b/")
    }

    @Test("A block shown as what not to do makes no line claims")
    func counterexample() {
        let text = "This doesn't work:\n" + fenced("logs/\n!logs/keep.log\nx # y")
        #expect(RuleBlocks.find(in: AnswerBlocks.split(text)).first?.isCounterexample == true)
        #expect(claims(text).isEmpty)
    }

    @Test("Unterminated and tilde fences")
    func fences() {
        #expect(AnswerBlocks.split("```gitignore\n*.log").count == 1)
        #expect(AnswerBlocks.split("~~~ gitignore\n*.log\n~~~\ntext").count == 2)
        #expect(AnswerBlocks.tag("```gitignore:.gitignore") == "gitignore")
    }
}

@Suite("Reading sentences")
struct SentenceTests {
    @Test("Span roles", arguments: [
        (".gitignore", Span.Role.ignoreFile), ("logs/.gitignore", .ignoreFile), ("~/.gitignore_global", .ignoreFile),
        (".git/info/exclude", .ignoreFile), ("!keep.log", .negation), ("*.log # logs", .pattern),
        ("git rm --cached x", .other), ("", .other), ("-v", .other), ("https://x.io", .other), ("*.log", .pattern),
        ("a=b", .other), ("...", .other), ("/build", .pattern), ("/a/b", .path), ("logs/app.log", .path),
        ("!", .other), ("# x", .other)
    ])
    func roles(_ text: String, _ role: Span.Role) {
        #expect(Span.role(of: text, blockLines: []) == role)
    }

    @Test("A code span equal to a line of the .gitignore is a pattern")
    func blockLine() {
        #expect(Span.role(of: "build", blockLines: ["build"]) == .pattern)
    }

    @Test("Hints from the words around a span")
    func hints() {
        func span(_ text: String, _ lead: String, _ tail: String = "") -> Span {
            Span(text: text, role: .path, lead: lead, tail: tail)
        }
        #expect(span("build/", "").isDirectoryHint == true)
        #expect(span("build", "the folder").isDirectoryHint == true)
        #expect(span("build", "a file named").isDirectoryHint == false)
        #expect(span("build", "", " file").isDirectoryHint == false)
        #expect(span("build", "x").isDirectoryHint == nil)
        #expect(span("x", "the contents of").isContainer)
        #expect(span("x", "inside").isContainer)
        #expect(!span("x", "").isContainer)
        #expect(!span("x", "one of").isContainer)
        #expect(span("x", "except").isException)
        #expect(span("x", "apart from").isException)
        #expect(!span("x", "").isException)
        #expect(span("x", "unlike").isContrasted)
        #expect(span("x", "use a rather than").isContrasted)
        #expect(!span("x", "").isContrasted)
        #expect(span("./a/", "").path == "a/")
        #expect(span("/a", "").path == "a")
    }

    @Test("Clauses split at breaks and cut at conditions")
    func clauses() {
        func count(_ text: String) -> Int { Clauses.split(Sentences.pieces(text)).count }
        #expect(count("`a` is ignored; `b` is kept") == 2)
        #expect(count("`a` is ignored, but `b` is kept") == 2)
        #expect(count("`a` is ignored and `b` is kept") == 2)
        #expect(count("`a` and `b` are ignored") == 1)
        #expect(Clauses.cut([.word("x"), .word("if"), .word("y")]) == [.word("x")])
        #expect(Clauses.words("It's, b; c!") == ["it's", ",", "b", ";", "c"])
        #expect(Sentences.split(["Use `a.b`, e.g. here. Then done."]).count == 2)
    }

    @Test("Verbs", arguments: [
        ("it brings `x` back", Lexicon.Polarity.kept), ("it shows up", .kept), ("it works", .works),
        ("it has no effect", .works), ("it does nothing", .works), ("it ignores", .ignored), ("it keeps", .kept),
        ("it appears in the status", .kept)
    ])
    func verbs(_ text: String, _ polarity: Lexicon.Polarity) {
        let tokens = Clauses.split(Sentences.pieces(text))[0].tokens
        #expect(Lexicon.verb(in: tokens)?.polarity == polarity)
    }

    @Test("Negations")
    func negations() {
        #expect(Lexicon.negationCount(["is", "no", "longer", "ignored"]) == 1)
        #expect(Lexicon.negationCount(["no", "slash"]) == 0)
        #expect(Lexicon.negationCount(["doesn't"]) == 1)
        #expect(Lexicon.negationCount(["no"]) == 0)
    }

    @Test("Hedges")
    func hedges() {
        #expect(SentenceReader.isHedged(["should", "be"]))
        #expect(SentenceReader.isHedged(["to"]))
        #expect(SentenceReader.isHedged(["must", "not", "be"]))
        #expect(!SentenceReader.isHedged(["will", "be"]))
        #expect(!SentenceReader.isHedged(["can't", "be"]))
        #expect(!SentenceReader.isHedged([]))
    }

    @Test("Sentences that make no claim", arguments: [
        "Does `*.log` ignore `logs/app.log`?",
        "Ignore `build/` with `build/`.",
        "You should ignore `node_modules/` and `.env`.",
        "To keep `.env.example`, add `!.env.example` after `.env*`.",
        "`build/` is ignored, and so is `dist/`.",
        "Check with `git check-ignore -v logs/app.log`, which prints the matching line.",
        "If you add `logs/`, `logs/keep.log` is ignored.",
        "The `.gitignore` template includes `*.xcuserstate` and `xcuserdata/`.",
        "This ignores `a.log`.",
        "`!keep.log` keeps it.",
        "`a.log` and `b.log` are ignored.",
        "`a` and `b` are anchored."
    ])
    func quiet(_ text: String) {
        #expect(claims(text).isEmpty)
    }

    @Test("Path claims against the sentence's own patterns")
    func sentenceRules() throws {
        let found = claims("`doc/*.txt` won't match `doc/a/b.txt` or `x/doc/c.txt`.")
        #expect(found.map(\.subject) == ["doc/a/b.txt", "x/doc/c.txt"])
        #expect(found.allSatisfy { $0.assertion == .notIgnored && $0.source == .sentence(["doc/*.txt"]) })
        let negated = try #require(claims("With `logs/` set, `!logs/keep.log` has no effect.").first)
        #expect(negated.subject == "logs/keep.log" && negated.assertion == .ignored)
        #expect(negated.source == .sentence(["logs/", "!logs/keep.log"]))
        let passive = try #require(claims("`logs/keep.log` stays ignored because of `logs/`.").first)
        #expect(passive.assertion == .ignored && passive.source == .sentence(["logs/"]))
        let out = try #require(claims("`*.log` keeps `app.log` out of the repo.").first)
        #expect(out.assertion == .ignored)
    }

    @Test("Path claims against the answer's .gitignore")
    func blockRules() throws {
        let answer = fenced("logs/*\n!logs/.gitkeep") + "\nEverything in `logs/` is ignored except `logs/.gitkeep`."
            + " It also ignores `logs/a.txt`, and `logs/b.txt` is ignored too."
        let found = claims(answer).filter(\.isExplicit)
        #expect(found.map(\.subject) == ["logs/.gitkeep", "logs/a.txt", "logs/b.txt"])
        #expect(found[0].assertion == .notIgnored && found[0].source == .block(1))
        let before = try #require(claims("This keeps `a.log`:\n" + fenced("*.log\n!a.log")).first)
        #expect(before.source == .block(1) && before.assertion == .notIgnored)
        let inherited = claims(fenced("*.log") + "\n`a.log` is ignored and is not tracked.")
        #expect(inherited.count == 1)
    }

    @Test("Scope claims")
    func scope() {
        let found = claims("`*.log` matches at any depth. `/build` only matches at the root. "
            + "`doc/*.txt` is anchored. `doc/*.txt` is not anchored. `a/b` doesn't match anywhere.")
        #expect(found.map(\.assertion) == [.anyDepth, .topLevelOnly, .topLevelOnly, .anyDepth, .topLevelOnly])
    }

    @Test("Another tool's ignore file")
    func foreign() throws {
        let claim = try #require(claims("In `.dockerignore`, `*.log` matches `logs/a.log`.").first)
        #expect(claim.source == .foreign(".dockerignore"))
        let block = try #require(claims("Add this `.dockerignore`:\n" + fenced("*.log", tag: "")
            + "\nIt also excludes `logs/app.log`.").first)
        #expect(block.source == .foreign(".dockerignore"))
    }

    @Test("Tracking claims")
    func tracking() {
        #expect(claims("Add `.env` to .gitignore to untrack it.").isEmpty)
        #expect(claims("Adding it to .gitignore won't stop tracking it.").map(\.assertion) == [.keepsTracking])
        #expect(claims("Adding it to .gitignore will stop tracking it.").map(\.assertion) == [.untracks])
        #expect(claims("Git will stop tracking it.").isEmpty)
        #expect(claims("Add it to .gitignore, then git rm it to stop tracking it.").isEmpty)
        #expect(claims("Add it to .gitignore. Then stop tracking it with `git rm --cached x`.").isEmpty)
        #expect(claims("Will .gitignore stop tracking it?").isEmpty)
        #expect(claims("If .gitignore could stop tracking it, life would be easy.").isEmpty)
    }

    @Test("Line claims")
    func lines() {
        let found = claims(fenced("\n# Logs\n*.log # logs\n!*.keep\n!keep/\n!a.txt\n!Makefile\nbuild/"))
        #expect(found.map(\.kind) == [.line, .path, .path, .path])
        #expect(found.compactMap(\.isDirectory) == [true, false])
        #expect(IgnoreClaimReader(checksLines: false).claims(in: fenced("*.log # logs")).isEmpty)
        #expect(LineReader.claims(in: RuleBlock(kind: .foreign("x"), lines: ["a # b"], position: 0, number: 1,
                                                isCounterexample: false), rules: IgnoreRules("")).isEmpty)
    }

    @Test("A sentence restating a line keeps only the sentence")
    func deduplication() {
        let found = claims(fenced("logs/\n!logs/keep.log") + "\n`logs/keep.log` is not ignored.")
        #expect(found.count == 1 && found[0].isExplicit)
    }

    @Test("A nested .gitignore always applies")
    func nested() throws {
        let answer = "In `logs/.gitignore`:\n" + fenced("*\n!.gitignore") + "\nSo `logs/today.txt` is ignored."
        let claim = try #require(claims(answer).first { $0.isExplicit })
        #expect(claim.rules?.files["logs/"] != nil)
    }
}
