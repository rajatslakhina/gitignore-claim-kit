/// "Add it to .gitignore and git stops tracking it": ignore rules only apply to files git does not track yet.
enum TrackingReader {
    static let untrack = ["stop tracking", "stops tracking", "stopped tracking", "untrack", "untracks",
                          "no longer track", "no longer tracks", "no longer be tracked", "no longer tracked",
                          "remove it from the repo", "removes it from the repo", "remove them from the repo",
                          "removes them from the repo", "remove it from git", "removes it from git",
                          "remove them from git", "removes them from git", "delete it from the repo",
                          "deletes it from the repo", "remove it from github", "removes it from github",
                          "remove it from the repository", "removes it from the repository",
                          "remove them from the repository", "removes them from the repository",
                          "remove the file from the repository", "removes the file from the repository",
                          "remove the file from the repo", "removes the file from the repo",
                          "remove it from the index", "removes it from the index", "remove it from history",
                          "removes it from history", "remove it from the history", "removes it from the history"]

    static func claims(in sentence: String, answer: String) -> [IgnoreClaim] {
        let folded = sentence.folded
        guard folded.contains("gitignore") || folded.contains("ignore file") || folded.contains("ignore list"),
              !answer.folded.contains("--cached"), !folded.contains("git rm"), !sentence.hasSuffix("?"),
              let phrase = untrack.first(where: { Words.contains(folded, $0) }),
              let range = folded.range(of: phrase) else { return [] }
        let before = Clauses.words(String(folded[..<range.lowerBound]))
        if SentenceReader.isHedged(before) || before.contains(where: Clauses.conditions.contains) { return [] }
        let negated = before.filter(Lexicon.isNegation).count % 2 == 1
        return [IgnoreClaim(kind: .tracking, subject: phrase, assertion: negated ? .keepsTracking : .untracks,
                            sentence: sentence)]
    }
}
