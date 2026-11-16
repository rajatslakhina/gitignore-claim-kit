#!/usr/bin/env python3
"""Regenerates Tests/GitignoreClaimKitTests/ParityFixture.swift from git itself.

Every case builds a throwaway repository, writes its .gitignore files, creates every path on disk (a path
ending in "/" is a directory) and asks `git check-ignore --no-index` about each one. Every file's answer is
cross-checked against `git status --porcelain --ignored -uall`; any disagreement stops the script.

Usage: python3 -I Scripts/parity.py > Tests/GitignoreClaimKitTests/ParityFixture.swift
"""
import os
import shutil
import subprocess
import sys
import tempfile

# (ignore files keyed by directory, core.ignorecase, paths). "" is the repository root.
CASES = [
    ({"": ["*.log"]}, False, ["a.log", "logs/app.log", "logs/debug/x.log", "a.log.txt", "log", ".log", "notes.LOG"]),
    ({"": ["/build"]}, False, ["build/", "build/out.o", "src/build/", "src/build/x"]),
    ({"": ["build/"]}, False, ["build/", "build/out.o", "src/build/", "src/build/x.o"]),
    ({"": ["build/"]}, False, ["build", "src/build", "app/build/"]),
    ({"": ["build"]}, False, ["build", "src/build/", "src/build/x.o", "builds/"]),
    ({"": ["doc/*.txt"]}, False, ["doc/a.txt", "doc/server/arch.txt", "a/doc/b.txt", "doc/.txt"]),
    ({"": ["doc/frotz/"]}, False, ["doc/frotz/", "a/doc/frotz/", "doc/frotz/x"]),
    ({"": ["frotz/"]}, False, ["frotz/", "a/frotz/", "a/frotz/x"]),
    ({"": ["**/foo"]}, False, ["foo", "a/foo", "a/b/foo", "c/foo/x"]),
    ({"": ["**/foo/bar"]}, False, ["foo/bar", "a/foo/bar", "a/b/foo/bar", "foo/baz"]),
    ({"": ["abc/**"]}, False, ["abc/", "abc/x", "abc/d/e", "xabc/y", "a/abc/x"]),
    ({"": ["a/**/b"]}, False, ["a/b", "a/x/b", "a/x/y/b", "a/xb", "b", "c/a/b"]),
    ({"": ["logs/", "!logs/keep.log"]}, False, ["logs/keep.log", "logs/app.log", "logs/"]),
    ({"": ["logs", "!logs/keep.log"]}, False, ["logs/keep.log", "logs/app.log"]),
    ({"": ["logs/*", "!logs/keep.log"]}, False, ["logs/keep.log", "logs/app.log", "logs/sub/keep.log", "logs/"]),
    ({"": ["logs/**", "!logs/keep.log"]}, False, ["logs/keep.log", "logs/app.log", "logs/sub/keep.log"]),
    ({"": ["/*", "!/foo", "/foo/*", "!/foo/bar"]}, False, ["foo/bar/x", "foo/baz", "top.txt", "foo/"]),
    ({"": ["*.log", "!important.log"]}, False, ["important.log", "x/important.log", "a.log"]),
    ({"": ["!important.log", "*.log"]}, False, ["important.log", "a.log"]),
    ({"": ["*.log # log files"]}, False, ["app.log", "a.log # log files"]),
    ({"": ["node_modules/  # dependencies"]}, False, ["node_modules/", "node_modules/x.js"]),
    ({"": ["\\#notes", "#comment"]}, False, ["#notes", "notes", "#comment"]),
    ({"": ["\\!important"]}, False, ["!important", "important"]),
    ({"": ["foo\\ ", "bar   "]}, False, ["foo ", "foo", "bar", "bar "]),
    ({"": ["*", "!*/", "!*.swift"]}, False, ["a.swift", "src/b.swift", "README.md", "src/c.md"]),
    ({"": ["[Bb]uild/"]}, False, ["Build/", "x/build/", "Builds/"]),
    ({"": ["*.[oa]"]}, False, ["x.o", "x.a", "x.c", "lib/y.a"]),
    ({"": ["?.txt"]}, False, ["a.txt", "ab.txt", "d/a.txt", ".txt"]),
    ({"": ["[!a]*.txt"]}, False, ["a1.txt", "b1.txt"]),
    ({"": ["[^a]*.md"]}, False, ["a1.md", "b1.md"]),
    ({"": ["[[:digit:]]*"]}, False, ["1abc", "abc", "x/2y"]),
    ({"": ["[a-c]x"]}, False, ["ax", "bx", "dx", "-x"]),
    ({"": [".env*", "!.env.example"]}, False, [".env", ".env.local", ".env.example", "config/.env"]),
    ({"": ["*.env"]}, False, [".env", "prod.env", "envs/dev.env"]),
    ({"": ["/node_modules"]}, False, ["node_modules/x.js", "packages/a/node_modules/y.js"]),
    ({"": ["node_modules/"]}, False, ["node_modules/x.js", "packages/a/node_modules/y.js"]),
    ({"": ["xcuserdata/", "*.xcuserstate", "*.xcodeproj/*", "!*.xcodeproj/project.pbxproj"]}, False,
     ["App.xcodeproj/project.pbxproj", "App.xcodeproj/xcuserdata/u.xcuserdatad/x.plist",
      "App.xcodeproj/project.xcworkspace/", "App.xcworkspace/xcuserdata/u.xcuserdatad/UserInterfaceState.xcuserstate",
      "Sub/App.xcodeproj/project.pbxproj"]),
    ({"": ["*.tmp"], "logs/": ["*", "!.gitignore"]}, False, ["logs/a.log", "logs/.gitignore", "a.tmp", "logs/b.tmp"]),
    ({"": ["*.log"], "sub/": ["!keep.log"]}, False, ["sub/keep.log", "keep.log", "sub/x.log"]),
    ({"": ["x/"], "x/": ["!keep"]}, False, ["x/keep", "x/other"]),
    ({"sub/": ["x/y", "/z"]}, False, ["sub/x/y", "x/y", "sub/z", "sub/a/z", "z"]),
    ({"": ["*.LOG"]}, True, ["app.log", "b.Log"]),
    ({"": ["Build/"]}, True, ["build/", "x/BUILD/"]),
    ({"": ["*.LOG"]}, False, ["app.log", "b.LOG"]),
    ({"": ["[B]uild/", "[a-c]x", "q[[:upper:]]", "\\Zed"]}, True, ["build/", "Cx", "qa", "zed"]),
    ({"": ["foo/**/"]}, False, ["foo/a/", "foo/a/x", "foo/b"]),
    ({"": ["*/"]}, False, ["x.txt", "a/b.txt", "a/c/"]),
    ({"": ["/a/b/"]}, False, ["a/b/", "x/a/b/", "a/b/c"]),
    ({"": ["a*b/c"]}, False, ["ab/c", "axyb/c", "x/ab/c"]),
    ({"": ["a/*/c"]}, False, ["a/b/c", "a/b/d/c", "a/c"]),
    ({"": ["**"]}, False, ["x", "a/b"]),
    ({"": ["/**/x"]}, False, ["x", "a/x", "a/b/x"]),
    ({"": ["***.txt"]}, False, ["a.txt", "d/b.txt"]),
    ({"": ["a/***/b"]}, False, ["a/b", "a/x/b"]),
    ({"": ["*.txt", "!/docs/*.txt"]}, False, ["docs/a.txt", "x/docs/a.txt", "b.txt"]),
    ({"": ["/vendor/*", "!/vendor/README.md"]}, False, ["vendor/README.md", "vendor/lib/x.c", "a/vendor/x"]),
    ({"": ["dist", "!dist/"]}, False, ["dist/", "dist/x.js", "src/dist"]),
    ({"": ["dist/", "!dist"]}, False, ["dist/", "dist/x.js"]),
    ({"": ["secrets.json", "!config/secrets.json"]}, False, ["config/secrets.json", "secrets.json", "a/secrets.json"]),
    ({"": ["*.swp", "*~", ".DS_Store"]}, False, ["a.swp", "b~", ".DS_Store", "x/.DS_Store", "DS_Store"]),
    ({"": ["Pods/", "!Pods/Manifest.lock"]}, False, ["Pods/Manifest.lock", "Pods/A/x.h"]),
    ({"": ["Pods/*", "!Pods/Manifest.lock"]}, False, ["Pods/Manifest.lock", "Pods/A/x.h"]),
    ({"": ["[]a]"]}, False, ["]", "a", "b"]),
    ({"": ["a[b"]}, False, ["a[b", "ab"]),
    ({"": ["x[[:alpha:]"]}, False, ["xa", "x1"]),
    ({"": ["\\*star"]}, False, ["*star", "xstar"]),
    ({"": ["a?c"]}, False, ["abc", "a/c"]),
]


def run(repo, *args):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)


def build(ignores, ignore_case, paths):
    repo = tempfile.mkdtemp(prefix="gitignore-parity-")
    try:
        run(repo, "init", "-q")
        run(repo, "config", "core.ignorecase", "true" if ignore_case else "false")
        for path in paths:
            target = os.path.join(repo, path)
            if path.endswith("/"):
                os.makedirs(target, exist_ok=True)
            else:
                os.makedirs(os.path.dirname(target), exist_ok=True)
                open(target, "w").close()
        for base, lines in ignores.items():
            os.makedirs(os.path.join(repo, base), exist_ok=True)
            with open(os.path.join(repo, base, ".gitignore"), "w") as handle:
                handle.write("\n".join(lines) + "\n")
        rows = []
        for path in paths:
            query = path.rstrip("/")
            code = run(repo, "check-ignore", "-q", "--no-index", "--", query).returncode
            if code not in (0, 1):
                sys.exit(f"git check-ignore failed on {path!r}")
            rows.append((path, code == 0))
        status = run(repo, "status", "--porcelain", "--ignored", "-uall", "-z").stdout.split("\0")
        ignored = [entry[3:] for entry in status if entry.startswith("!! ")]
        untracked = [entry[3:] for entry in status if entry.startswith("?? ")]
        for path, verdict in rows:
            if path.endswith("/") or path.endswith(".gitignore"):
                continue
            listed = path in ignored or any(path.startswith(d) for d in ignored if d.endswith("/"))
            shown = path in untracked
            if listed != verdict or shown == verdict:
                sys.exit(f"check-ignore and status disagree on {path!r} for {ignores!r}")
        return rows
    finally:
        shutil.rmtree(repo)


def swift(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    version = subprocess.run(["git", "--version"], capture_output=True, text=True).stdout.strip()
    out = [f"// Generated by Scripts/parity.py from {version}. Do not edit by hand.", "",
           "@testable import GitignoreClaimKit", "",
           "struct ParityCase {", "    let files: [String: [String]]", "    let ignoreCase: Bool",
           "    let rows: [(path: String, ignored: Bool)]", "}", "",
           "let parityCases: [ParityCase] = ["]
    for ignores, ignore_case, paths in CASES:
        files = ", ".join(f"{swift(base)}: [{', '.join(swift(line) for line in lines)}]"
                          for base, lines in ignores.items())
        rows = ", ".join(f"({swift(path)}, {'true' if verdict else 'false'})"
                         for path, verdict in build(ignores, ignore_case, paths))
        out.append(f"    ParityCase(files: [{files}], ignoreCase: {'true' if ignore_case else 'false'},")
        out.append(f"               rows: [{rows}]),")
    out.append("]")
    print("\n".join(out))


if __name__ == "__main__":
    main()
