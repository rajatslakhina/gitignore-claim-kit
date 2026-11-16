import Testing
@testable import GitignoreClaimKit

/// Answers collected while probing the reader before tagging: correct ones must raise nothing, wrong ones
/// must be caught.
enum Probes {
    static let correct: [String] = [
        "Here is a typical `.gitignore` for an Xcode project:\n\n```gitignore\n# Xcode\nxcuserdata/\n*.xcuserstate\nDerivedData/\n\n# Swift Package Manager\n.build/\n\n# CocoaPods\nPods/\n\n# Logs\nlogs/*\n!logs/.gitkeep\n```\n\nThe `logs/*` line ignores the contents of `logs/` while `!logs/.gitkeep` keeps the placeholder, so the folder itself stays in the repository. `DerivedData/` is ignored at any depth because it has no leading slash. If you only want the root one, use `/DerivedData/` instead.",
        "Note that `.gitignore` does not untrack files that are already committed. Run `git rm --cached config.json` to stop tracking it.",
        "A `.gitignore` line like `*.log` matches log files in every directory, so `logs/debug/app.log` is ignored too. Unlike `logs/`, `logs/*` lets `!logs/keep.log` bring the file back.",
        "Use `/build` rather than `build` if you only want to ignore the top-level folder. `doc/*.txt` won't match `doc/server/arch.txt`; use `doc/**/*.txt` for that.",
        "You should ignore `node_modules/` and `.env`. To keep `.env.example`, add `!.env.example` after `.env*`.",
        "Adding `*.log` to `.gitignore` keeps `app.log` out of the repo.",
        "`a/**/b` matches `a/b`, `a/x/b` and `a/x/y/b`.",
        "How do I ignore `build/` but keep `build/README.md`? Ignore the contents with `build/*` and re-include the file with `!build/README.md`.",
        "With `logs/` in your `.gitignore`, `!logs/keep.log` has no effect: `logs/keep.log` stays ignored.",
        "The `.dockerignore` below excludes `node_modules` from the build context:\n\n```\nnode_modules\n*.log\n```",
        "Will `*.LOG` ignore `app.log`? On macOS it does, because `core.ignorecase` is true there.",
        "In a `.gitignore`, `/node_modules` only matches the `node_modules` folder at the root.",
        "Your `.gitignore` has `logs/` on one line and `!logs/keep.log` on the next. That doesn't work, because git never looks inside an excluded directory. Change it to this:\n\n```gitignore\nlogs/*\n!logs/keep.log\n```\n\nNow `logs/keep.log` is tracked and every other file in `logs/` is ignored.",
        "This doesn't work:\n\n```gitignore\nlogs/\n!logs/keep.log\n```\n\nUse `logs/*` instead.",
        "Add these lines:\n\n```\n# .gitignore\n.env\n.env.*\n!.env.example\n```\n\n`.env` and `.env.local` are ignored, while `.env.example` stays tracked so teammates can copy it.",
        "A pattern without a slash, like `*.log`, matches at any level. A pattern with a slash in the middle, like `doc/*.txt`, is anchored to the directory of the `.gitignore`. A trailing slash, as in `build/`, matches only directories.",
        "If `config.json` is already tracked, adding it to `.gitignore` won't stop tracking it.",
        "Put a `.gitignore` inside `logs/` containing `*` and `!.gitignore`, so the folder is kept but its contents are not.",
        "The `**/temp` pattern matches `temp` anywhere, for example `src/temp` and `a/b/temp`.",
        "`.DS_Store` is ignored in every folder because the pattern has no slash.",
        "In `.gitignore`, `#` only starts a comment at the beginning of a line, so `*.log # logs` would not ignore `app.log`.",
        "Here's the `logs/.gitignore`:\n\n```gitignore\n*\n!.gitignore\n```\n\nEverything in `logs/` is ignored except `logs/.gitignore` itself.",
        "Remember that the order matters: `!important.log` must come after `*.log`, otherwise `important.log` is still ignored.",
        "The rule `build` (no slash) ignores both a `build` file and a `build/` folder, at any depth.",
        "`Pods/` ignores the whole directory, so `!Pods/Manifest.lock` cannot bring `Pods/Manifest.lock` back.",
        "To ignore all `.log` files except `important.log`, add `*.log` followed by `!important.log`.",
        "```gitignore\n*.log\n!important.log\n```\n\nWith these two lines, `debug.log` is ignored but `important.log` is not.",
        "`build/` is ignored, and so is `dist/`.",
        "Git will not ignore `src/app.swift` with this file, but it will ignore `build/output.o` and `.DS_Store`.\n\n```gitignore\nbuild/\n.DS_Store\n```",
        "You can't re-include a file if its parent directory is excluded, which is why `!logs/keep.log` doesn't work after `logs/`.",
        "The `/*` at the start ignores everything at the root, then `!/src` brings `src` back.",
        "Note: patterns like `foo/bar` are relative to the `.gitignore` location, so `foo/bar` in the root `.gitignore` doesn't match `a/foo/bar`.",
        "`node_modules` (without a trailing slash) matches both files and directories named `node_modules`.",
        "Files that are already tracked are not affected by `.gitignore`; use `git rm -r --cached .` to untrack them.",
        "To stop tracking a file that is already committed, run `git rm --cached file`, then add it to `.gitignore`.",
        "Make sure `.env` is listed in `.gitignore` so it is never committed.",
        "The `.gitignore` template from GitHub includes `*.xcuserstate` and `xcuserdata/`.",
        "Check with `git check-ignore -v logs/app.log`, which prints the matching line.",
        "Does `*.log` ignore `logs/app.log`? Yes, a pattern without a slash matches at any depth.",
    ]

    /// Sentences about regexes, collections, globs and version ranges: without an ignore file in view they make
    /// no claim about ignore rules. 1.0.0 read the first span of each as a .gitignore pattern.
    static let otherDomains: [String] = [
        "`[a-z]+` matches `abc`.", "`.*` matches `anything`.", "`compactMap` ignores `nil` values.",
        "`~1.2` matches `1.2.5`.", "`Set` excludes `duplicates`.", "The regex `^\\d+$` matches `123` but not `12a`.",
        "`grep -v` excludes `error` lines.", "`*.swift` matches `main.swift` in the shell.",
        "With npm, `^0.2.3` allows 0.3.0.", "The glob `src/*.ts` matches `src/a/b.ts`.",
        "`filter` keeps `even` numbers and excludes `odd` ones.", "`*` matches `.hidden` in bash only with dotglob.",
        "`NSPredicate` with `LIKE` matches `a*c` against `abc`.", "The route `/users/*` matches `/users/42`.",
        "In Python, `fnmatch('a/b', '*')` matches.",
    ]

    static let wrong: [String] = [
        "To keep one log file, add this to your `.gitignore`:\n\n```gitignore\nlogs/\n!logs/keep.log\n*.tmp # temp files\n```\n\nThis ignores everything in `logs/` but keeps `logs/keep.log` tracked.",
        "The pattern `doc/*.txt` matches `doc/server/arch.txt` as well.",
        "`build/` also ignores a file named `build`.",
        "`*.log` only matches log files at the root of the repository.",
        "`config/secrets.json` matches at any depth.",
        "Just add `.env` to your .gitignore and git will stop tracking it.",
        "In your `.gitignore`, `a/**/b` won't match `a/b`.",
        "`*.env` doesn't match `.env`, because `*` skips dotfiles.",
    ]
}

@Suite("Probe answers")
struct ProbeTests {
    @Test("Correct answers raise nothing, with or without a question about .gitignore", arguments: Probes.correct)
    func correct(_ answer: String) {
        let report = check(answer)
        #expect(report.flagged.isEmpty, "\(report.corrections)")
        #expect(IgnoreClaimChecker().check(answer).flagged.isEmpty)
    }

    @Test("Sentences about other things make no claim when nothing mentions an ignore file",
          arguments: Probes.otherDomains)
    func otherDomains(_ sentence: String) {
        #expect(IgnoreClaimChecker().check(sentence).verdict == .noClaims)
        #expect(!IgnoreClaimReader.isAboutIgnoreRules(sentence))
    }

    @Test("Wrong answers are caught in a conversation about .gitignore", arguments: Probes.wrong)
    func wrong(_ answer: String) {
        #expect(check(answer).verdict == .wrong)
    }

    @Test("An answer that names .gitignore needs no context; one that does not, does")
    func context() {
        #expect(IgnoreClaimChecker().check("In a `.gitignore`, `*.log` doesn't match `x/a.log`.").verdict == .wrong)
        #expect(IgnoreClaimChecker().check("`*.log` doesn't match `x/a.log`.").verdict == .noClaims)
        #expect(IgnoreClaimChecker().check("`*.log` doesn't match `x/a.log`.", context: "my .dockerignore").verdict
            == .unchecked)
        #expect(IgnoreClaimReader.isAboutIgnoreRules("Run git check-ignore -v"))
        let block = "```ignore\n*.log\n```\nThis ignores `a.log`."
        #expect(IgnoreClaimChecker().check(block, context: "my .dockerignore").findings.first?.claim.source == .block(1))
    }
}
