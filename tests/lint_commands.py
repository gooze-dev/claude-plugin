"""Check that the plugin only tells Claude to run gooze and goozels commands
that exist.

Scans the skills and README for `gooze ...` and `goozels ...` invocations in code spans and code
blocks and rejects unknown subcommands and flags. Keep KNOWN in sync with
`gooze --help` for the gooze version the plugin targets (see
skills/init/guide.md).

Usage: python3 tests/lint_commands.py   (exit status 1 on problems)
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

GLOBAL_FLAGS = {"-x", "--exclude", "-o", "--output", "--no-cache", "-v", "--verbose", "--log-output", "-h", "--help"}

# subcommand path -> flags it accepts besides the global ones.
KNOWN = {
    # --diff, --run and --mutagens arrive after v1.2.0; the skills say so.
    "run": {"-p", "--parallel", "-s", "--shard", "--estimate", "--mutation-timeout", "--coverage-profile", "--diff", "--run", "--mutagens"},
    "report view": {"--all"},
    "report merge": set(),
    "report push": {"--plain-http", "--insecure"},
    "report pull": {"--plain-http", "--insecure"},
    "report": set(),
    "config init": set(),
    "config": set(),
    "version": set(),
    "help": set(),
    "completion": set(),
}

# goozels subcommands and their flags (Go's flag package accepts -x and --x).
GOOZELS = {
    "check": {"-workdir", "--workdir", "-max", "--max"},
    "hook claude": set(),
    "hook codex": set(),
    "version": {"-json"},
    "help": set(),
    "serve": set(),
}
GOOZELS_FLAGS = {"-gopls", "--gopls", "-gooze", "--gooze", "-h", "-help", "--help"}

TOOLS = {"gooze": (KNOWN, GLOBAL_FLAGS), "goozels": (GOOZELS, GOOZELS_FLAGS)}

BLOCK = re.compile(r"```[a-z]*\n(.*?)```", re.S)
SPAN = re.compile(r"`([^`\n]+)`")
# gooze in command position: line start (after YAML "run:", a list dash or a
# "$ " prompt), after a shell separator, or after exec/env assignments.
INVOCATION = re.compile(
    r"(?:^\s*(?:-\s+)?(?:run:\s*|script:\s*|\$\s+)?|[;&|(]\s*|\$\(\s*|\bexec\s+|\b[A-Z_]+=\S*\s+)"
    r"(goozels|gooze)\b((?:[ \t]+[^\s|;&)`'\"]+)*)"
)
COMMENT = re.compile(r"(?:^|\s)(?:#|//).*$")
PROSE_KEYS = re.compile(r"^\s*(?:-\s+)?(?:name|desc|description):")
IGNORE = "lint-ignore"


def subcommand(known, words):
    """Return the longest known subcommand path at the start of words."""
    for n in (2, 1):
        path = " ".join(words[:n])
        if len(words) >= n and path in known:
            return path, words[n:]
    return None, words


def looks_like_prose(words):
    """Three or more plain words and no flag, path or variable: a sentence or
    quoted tool output, not a command line."""
    return len(words) >= 3 and not any(w[0] in "-./$~" for w in words)


def commands(text):
    """Yield the command lines worth checking: code-block lines without
    comments or YAML prose keys, and inline code spans; lines marked
    lint-ignore are skipped."""
    for block in BLOCK.finditer(text):
        for line in block.group(1).splitlines():
            if IGNORE not in line and not PROSE_KEYS.match(line):
                yield COMMENT.sub("", line)
    for line in BLOCK.sub("", text).splitlines():
        if IGNORE not in line:
            yield from SPAN.findall(line)


def check(path):
    problems = []
    for line in commands(path.read_text()):
        for m in INVOCATION.finditer(line):
            tool, words = m.group(1), m.group(2).split()
            known, tool_flags = TOOLS[tool]
            if not words or words[0].startswith(("<", "$", "{", "[")):
                continue  # placeholder or prose like "gooze <subcommand>"
            if tool == "goozels" and words[0].startswith("-"):
                words = [w for w in words if w.split("=", 1)[0] not in tool_flags]
                if not words:
                    continue  # language-server invocation with flags only
            sub, rest = subcommand(known, words)
            where = f"{path.relative_to(ROOT)}: `{tool} {' '.join(words)}`"
            if sub is None and re.match(r"v?\d", words[0]):
                continue  # version output such as "gooze v1.2.0 (go1.27.3)"
            if sub is None and looks_like_prose(words):
                continue  # quoted output such as "gooze results from the last run:"
            if sub is None:
                problems.append(f"{where}: unknown subcommand {words[0]!r}")
                continue
            allowed = known[sub] | tool_flags
            for w in rest:
                flag = w.split("=", 1)[0]
                if flag.startswith("-") and flag not in allowed:
                    problems.append(f"{where}: unknown flag {flag!r} for '{tool} {sub}'")
    return problems


def main():
    files = sorted(ROOT.glob("skills/**/*.md")) + [ROOT / "README.md"]
    problems = [p for f in files for p in check(f)]
    for p in problems:
        print(p)
    print(f"checked {len(files)} files, {len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
