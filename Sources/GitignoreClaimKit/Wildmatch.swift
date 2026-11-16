/// git's glob matcher (`wildmatch.c`), ported byte for byte so that `*`, `**`, `?`, bracket classes and
/// backslash escapes behave the way they do in a .gitignore.
enum Wildmatch {
    struct Flags: OptionSet, Sendable {
        let rawValue: Int
        /// `*` and `?` stop at `/`; `**` between slashes crosses them.
        static let pathname = Flags(rawValue: 1)
        /// Letters compare without case (`core.ignorecase`).
        static let caseFold = Flags(rawValue: 2)
    }

    enum Result: Equatable {
        case match, noMatch, abortAll, abortToStarStar
    }

    static func matches(_ pattern: String, _ text: String, flags: Flags) -> Bool {
        Matcher(pattern: Array(pattern.utf8), text: Array(text.utf8), flags: flags).run(0, 0) == .match
    }
}

private let star = UInt8(ascii: "*")
private let slash = UInt8(ascii: "/")
private let backslash = UInt8(ascii: "\\")
private let question = UInt8(ascii: "?")
private let open = UInt8(ascii: "[")
private let close = UInt8(ascii: "]")
private let dash = UInt8(ascii: "-")
private let colon = UInt8(ascii: ":")

private struct Matcher {
    let pattern: [UInt8]
    let text: [UInt8]
    let flags: Wildmatch.Flags

    var pathname: Bool { flags.contains(.pathname) }
    var fold: Bool { flags.contains(.caseFold) }

    /// The byte at `index`, or 0 past the end (C's terminating NUL).
    func pat(_ index: Int) -> UInt8 { index < pattern.count ? pattern[index] : 0 }
    func txt(_ index: Int) -> UInt8 { index < text.count ? text[index] : 0 }

    func folded(_ byte: UInt8) -> UInt8 { fold ? ASCII.lower(byte) : byte }

    enum Step {
        case done(Wildmatch.Result)
        /// Carry on after these pattern and text positions.
        case skipTo(Int, Int)
    }

    /// A bracket member: where it ends, the byte that counts as the previous one for a following `-`, and
    /// whether the text byte matched it.
    struct Member {
        let end: Int
        let byte: UInt8
        let matched: Bool
    }

    func run(_ start: Int, _ textStart: Int) -> Wildmatch.Result {
        var pi = start
        var ti = textStart
        while pat(pi) != 0 {
            switch step(pi, ti) {
            case .done(let result): return result
            case .skipTo(let next, let nextText):
                pi = next + 1
                ti = nextText + 1
            }
        }
        return txt(ti) != 0 ? .noMatch : .match
    }

    /// One pattern byte (or escape, star run, or bracket) against the text at `ti`.
    func step(_ pi: Int, _ ti: Int) -> Step {
        let tch = folded(txt(ti))
        let pch = folded(pat(pi))
        if txt(ti) == 0 && pch != star { return .done(.abortAll) }
        switch pch {
        case backslash:
            return tch == pat(pi + 1) ? .skipTo(pi + 1, ti) : .done(.noMatch)
        case question:
            return pathname && tch == slash ? .done(.noMatch) : .skipTo(pi, ti)
        case star:
            return starStep(at: pi + 1, ti)
        case open:
            return bracketStep(at: pi + 1, tch, ti)
        default:
            return tch == pch ? .skipTo(pi, ti) : .done(.noMatch)
        }
    }

    /// The `*` case. `index` is the byte after the first star.
    func starStep(at index: Int, _ ti: Int) -> Step {
        guard let (pi, matchSlash) = stars(from: index, ti) else { return .done(.match) }
        if pat(pi) == 0 {
            return .done(!matchSlash && text[ti...].contains(slash) ? .noMatch : .match)
        }
        if !matchSlash, pat(pi) == slash {
            guard let next = text[ti...].firstIndex(of: slash) else { return .done(.noMatch) }
            return .skipTo(pi, next)
        }
        return .done(scan(pi, ti, matchSlash))
    }

    /// Where the pattern resumes after a run of stars, and whether the run may cross `/`. `nil` when a
    /// `**/` that matches no directory already matched the rest.
    func stars(from index: Int, _ ti: Int) -> (Int, Bool)? {
        var pi = index
        guard pat(pi) == star else { return (pi, !pathname) }
        let previous = pi - 2
        pi += 1
        while pat(pi) == star { pi += 1 }
        guard pathname else { return (pi, true) }
        let opens = previous < 0 || pat(previous) == slash
        let closes = pat(pi) == 0 || pat(pi) == slash || (pat(pi) == backslash && pat(pi + 1) == slash)
        if opens, closes, pat(pi) == slash, run(pi + 1, ti) == .match { return nil }
        return (pi, opens && closes)
    }

    /// Tries the rest of the pattern at each text position the stars could stop at.
    func scan(_ pi: Int, _ start: Int, _ matchSlash: Bool) -> Wildmatch.Result {
        var ti = start
        var tch = folded(txt(ti))
        while tch != 0 {
            if !ASCII.isGlobSpecial(pat(pi)) {
                guard let found = fastForward(pi, ti, matchSlash) else {
                    return matchSlash ? .abortAll : .abortToStarStar
                }
                ti = found
                tch = folded(txt(ti))
            }
            let matched = run(pi, ti)
            if matched != .noMatch {
                if !matchSlash || matched != .abortToStarStar { return matched }
            } else if !matchSlash && tch == slash {
                return .abortToStarStar
            }
            ti += 1
            tch = txt(ti)
        }
        return .abortAll
    }

    /// The first text position from `start` holding the literal byte after the stars, without crossing `/`
    /// unless the stars may.
    func fastForward(_ pi: Int, _ start: Int, _ matchSlash: Bool) -> Int? {
        let target = folded(pat(pi))
        var ti = start
        while txt(ti) != 0, matchSlash || txt(ti) != slash {
            if folded(txt(ti)) == target { return ti }
            ti += 1
        }
        return nil
    }

    /// The `[...]` case. `index` is the byte after `[`; `tch` is the text byte being matched.
    func bracketStep(at index: Int, _ tch: UInt8, _ ti: Int) -> Step {
        var pi = index
        let negated = pat(pi) == UInt8(ascii: "!") || pat(pi) == UInt8(ascii: "^")
        if negated { pi += 1 }
        guard let (end, matched) = members(from: pi, tch) else { return .done(.abortAll) }
        if matched == negated || (pathname && tch == slash) { return .done(.noMatch) }
        return .skipTo(end, ti)
    }

    /// Walks a bracket's members up to its closing `]`: that index, and whether `tch` matched any member.
    /// `nil` for a malformed bracket.
    func members(from start: Int, _ tch: UInt8) -> (Int, Bool)? {
        var pi = start
        var previous: UInt8 = 0
        var matched = false
        repeat {
            guard pat(pi) != 0, let member = member(at: pi, previous, tch) else { return nil }
            matched = matched || member.matched
            previous = member.byte
            pi = member.end + 1
        } while pat(pi) != close
        return (pi, matched)
    }

    func member(at index: Int, _ previous: UInt8, _ tch: UInt8) -> Member? {
        let pch = pat(index)
        if pch == backslash {
            let escaped = pat(index + 1)
            return escaped == 0 ? nil : Member(end: index + 1, byte: escaped, matched: tch == escaped)
        }
        if pch == dash, previous != 0, pat(index + 1) != 0, pat(index + 1) != close {
            return range(at: index + 1, from: previous, tch)
        }
        if pch == open, pat(index + 1) == colon { return namedClass(at: index + 2, tch) }
        return Member(end: index, byte: pch, matched: tch == pch)
    }

    /// `a-z`: `index` is the byte after `-`.
    func range(at index: Int, from low: UInt8, _ tch: UInt8) -> Member? {
        var pi = index
        if pat(pi) == backslash {
            pi += 1
            if pat(pi) == 0 { return nil }
        }
        let high = pat(pi)
        let upper = ASCII.upper(tch)
        let hit = (tch <= high && tch >= low) || (fold && ASCII.isLower(tch) && upper <= high && upper >= low)
        return Member(end: pi, byte: 0, matched: hit)
    }

    /// `[:name:]` inside a bracket. `start` is the byte after `[:`. Without a closing `:]` the `[` is an
    /// ordinary member and matching resumes right after it.
    func namedClass(at start: Int, _ tch: UInt8) -> Member? {
        var pi = start
        while pat(pi) != 0 && pat(pi) != close { pi += 1 }
        if pat(pi) == 0 { return nil }
        let length = pi - start - 1
        if length < 0 || pat(pi - 1) != colon { return Member(end: start - 2, byte: open, matched: tch == open) }
        let name = String(pattern[start..<(start + length)].map { Character(Unicode.Scalar($0)) })
        guard let hit = ASCII.inClass(name, tch, fold: fold) else { return nil }
        return Member(end: pi, byte: 0, matched: hit)
    }
}

/// The C locale's character tests, which is what git uses.
enum ASCII {
    static func isLower(_ byte: UInt8) -> Bool { byte >= 97 && byte <= 122 }
    static func isUpper(_ byte: UInt8) -> Bool { byte >= 65 && byte <= 90 }
    static func isDigit(_ byte: UInt8) -> Bool { byte >= 48 && byte <= 57 }
    static func lower(_ byte: UInt8) -> UInt8 { isUpper(byte) ? byte + 32 : byte }
    static func upper(_ byte: UInt8) -> UInt8 { isLower(byte) ? byte - 32 : byte }
    static func isGlobSpecial(_ byte: UInt8) -> Bool { [star, question, open, backslash].contains(byte) }

    /// Whether `byte` is in the named class; `nil` for a name git does not know.
    static func inClass(_ name: String, _ byte: UInt8, fold: Bool) -> Bool? {
        classes[name].map { $0(byte, fold) }
    }

    static func isAlpha(_ byte: UInt8) -> Bool { isLower(byte) || isUpper(byte) }
    static func isGraph(_ byte: UInt8) -> Bool { byte >= 0x21 && byte <= 0x7e }

    static let classes: [String: @Sendable (UInt8, Bool) -> Bool] = [
        "alnum": { byte, _ in isAlpha(byte) || isDigit(byte) },
        "alpha": { byte, _ in isAlpha(byte) },
        "blank": { byte, _ in byte == 0x20 || byte == 0x09 },
        "cntrl": { byte, _ in byte < 0x20 || byte == 0x7f },
        "digit": { byte, _ in isDigit(byte) },
        "graph": { byte, _ in isGraph(byte) },
        "lower": { byte, _ in isLower(byte) },
        "print": { byte, _ in byte >= 0x20 && byte <= 0x7e },
        "punct": { byte, _ in isGraph(byte) && !isAlpha(byte) && !isDigit(byte) },
        "space": { byte, _ in [0x20, 0x09, 0x0a, 0x0b, 0x0c, 0x0d].contains(byte) },
        "upper": { byte, fold in isUpper(byte) || (fold && isLower(byte)) },
        "xdigit": { byte, _ in isDigit(byte) || (byte >= 97 && byte <= 102) || (byte >= 65 && byte <= 70) }
    ]
}
