import GitignoreClaimKit

enum Scenarios {
    static func reinclude() {
        scenario(1, "Keeping one file in an ignored folder")
        let wrong = """
        Add this to your `.gitignore`:

        ```gitignore
        logs/
        !logs/keep.log
        ```

        This ignores everything in `logs/` but keeps `logs/keep.log` tracked.
        """
        show("answer", IgnoreClaimChecker().check(wrong))
        let rules = IgnoreRules("logs/\n!logs/keep.log\n")
        explain(rules, "logs/keep.log")
        let right = """
        Ignore the folder's contents instead of the folder:

        ```gitignore
        logs/*
        !logs/keep.log
        ```

        Now `logs/keep.log` is tracked, and `logs/app.log` is ignored.
        """
        show("rewrite", IgnoreClaimChecker().check(right))
        explain(IgnoreRules("logs/*\n!logs/keep.log\n"), "logs/keep.log")
    }

    static func trailingComment() {
        scenario(2, "A comment after a pattern")
        let answer = """
        A starter `.gitignore` for a Swift package:

        ```gitignore
        .build/        # build products
        *.xcuserstate
        .DS_Store
        ```

        With this file `.build/debug/App.o` is ignored.
        """
        show("answer", IgnoreClaimChecker().check(answer))
        explain(IgnoreRules(".build/        # build products\n"), ".build/debug/App.o")
    }

    static func anchoring() {
        scenario(3, "Where a pattern matches")
        let answer = """
        `*.log` only matches log files at the root of the repository. `doc/*.txt` matches \
        `doc/server/arch.txt` as well. `config/secrets.json` matches at any depth. \
        `/build` only ignores the top-level `build` folder.
        """
        show("answer", IgnoreClaimChecker().check(answer))
        let rules = IgnoreRules("*.log\ndoc/*.txt\n")
        for path in ["logs/debug/app.log", "doc/server/arch.txt", "doc/readme.txt"] { explain(rules, path) }
    }

    static func directories() {
        scenario(4, "A trailing slash, and ** between slashes")
        let answer = """
        `build/` also ignores a file named `build`. In a `.gitignore`, `a/**/b` won't match `a/b`, \
        and `*.env` doesn't match `.env`.
        """
        show("answer", IgnoreClaimChecker().check(answer))
    }

    static func tracking() {
        scenario(5, "Ignoring a file that is already committed")
        let wrong = "Just add `.env` to your .gitignore and git will stop tracking it."
        show("answer", IgnoreClaimChecker().check(wrong))
        let right = """
        A `.gitignore` entry does not stop tracking a file that is already committed. \
        Run `git rm --cached .env` first, then commit.
        """
        show("rewrite", IgnoreClaimChecker().check(right))
    }

    static func letterCase() {
        scenario(6, "Upper and lower case")
        let answer = """
        ```gitignore
        *.LOG
        ```

        `app.log` is ignored as well.
        """
        show("standard (core.ignorecase unknown)", IgnoreClaimChecker().check(answer))
        show("caseSensitive (Linux, CI)", IgnoreClaimChecker(policy: .caseSensitive).check(answer))
        show("caseInsensitive (macOS, Windows)", IgnoreClaimChecker(policy: .caseInsensitive).check(answer))
    }

    static func nested() {
        scenario(7, "A .gitignore inside a folder, and another tool's ignore file")
        let answer = """
        Put this in `logs/.gitignore`:

        ```gitignore
        *
        !.gitignore
        ```

        Everything in `logs/` is ignored except `logs/.gitignore`, and `logs/today.txt` is ignored.
        """
        show("answer", IgnoreClaimChecker().check(answer))
        let docker = """
        Add this `.dockerignore`:

        ```
        *.log
        ```

        It also excludes `logs/app.log` from the build context.
        """
        show("dockerignore", IgnoreClaimChecker().check(docker))
    }

    static func conversation() async {
        scenario(8, "A conversation: the same mistake after a correction")
        let ledger = IgnoreLedger()
        let first = "`doc/*.txt` matches `doc/server/arch.txt` too, and `*.log` only matches at the root."
        let firstReport = await ledger.review(first)
        show("turn 1", firstReport)
        if let feedback = firstReport.feedback {
            print("   feedback sent: \(feedback.split(separator: "\n").count) lines")
        }
        let second = "Sorry: `*.log` matches at any depth. And `doc/*.txt` still matches `doc/server/arch.txt`."
        show("turn 2", await ledger.review(second))
        let stats = await ledger.statistics
        print("   ledger: \(stats.reviews) reviews, \(stats.claims) claims, \(stats.flagged) flagged, "
              + "\(stats.repeated) repeated")
    }
}
