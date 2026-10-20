#!/bin/sh
# Tests for the plugin's hook scripts: the SessionStart preflight
# (scripts/session-start.sh) and the PostToolUse guard in hooks/hooks.json.
# Tools are faked with small scripts on PATH, so no real gooze or goozels is
# needed. Override SESSION_START or HOOKS_JSON to test other copies (the
# mutation check in tests/mutate.sh does that).
#
# Usage: sh tests/run.sh    (exit status is the number of failures, capped)

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SESSION_START=${SESSION_START:-$ROOT/scripts/session-start.sh}
HOOKS_JSON=${HOOKS_JSON:-$ROOT/hooks/hooks.json}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fails=0
passes=0

pass() { passes=$((passes + 1)); }
fail() {
	fails=$((fails + 1))
	printf 'FAIL: %s\n' "$1"
	[ -n "$2" ] && printf '  got: %s\n' "$2"
}

# --- fake tools ------------------------------------------------------------

BIN=$TMP/bin
mkdir -p "$BIN/gooze" "$BIN/goozels-new" "$BIN/goozels-old" "$BIN/none"

# gooze prints its version on stderr, as the real binary does.
cat >"$BIN/gooze/gooze" <<'EOF'
#!/bin/sh
[ "$1" = version ] && echo "gooze version v1.1.1" >&2
exit 0
EOF

# goozels with agent-hook support identifies itself on "version"; "hook"
# records its arguments and stdin so tests can check they were passed on.
cat >"$BIN/goozels-new/goozels" <<EOF
#!/bin/sh
case "\$1" in
version) echo "goozels v0.2.0" ;;
hook) echo "\$*" >"$TMP/hook-args"; cat >"$TMP/hook-stdin"; echo '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"ok"}}' ;;
esac
EOF

# goozels v0.1.0 passes unknown arguments to gopls: "version" prints gopls's
# version, and "hook" would start a language server.
cat >"$BIN/goozels-old/goozels" <<EOF
#!/bin/sh
case "\$1" in
version) echo "golang.org/x/tools/gopls v0.20.0" ;;
hook) echo called >"$TMP/old-hook-called"; exit 2 ;;
esac
EOF

chmod +x "$BIN"/*/*
SYS=/usr/bin:/bin

# --- helpers -----------------------------------------------------------------

# go_project DIR: a Go module with nothing else in it.
go_project() {
	rm -rf "$1"
	mkdir -p "$1"
	echo "module example.com/x" >"$1/go.mod"
}

# plugin_root GUIDE: a plugin root whose guide.md has that guide version
# ("" for a plugin without guide.md).
plugin_root() {
	r=$TMP/plugin-$1
	mkdir -p "$r/skills/init"
	[ -n "$1" ] && printf '<!-- gooze:begin guide=%s gooze=v1.1.1 -->\nguide\n<!-- gooze:end -->\n' "$1" >"$r/skills/init/guide.md"
	echo "$r"
}

# preflight DIR PATH [PLUGIN_ROOT]: run the SessionStart script; stdout only.
preflight() {
	(cd "$1" && env PATH="$2" CLAUDE_PLUGIN_ROOT="${3:-$(plugin_root 1)}" sh "$SESSION_START" 2>"$TMP/stderr")
}

# message JSON: the systemMessage, or "" when the output is not hook JSON.
message() {
	printf '%s' "$1" | python3 -c 'import json,sys
d=json.load(sys.stdin)
assert d["hookSpecificOutput"]["hookEventName"] == "SessionStart"
assert d["hookSpecificOutput"]["additionalContext"] == d["systemMessage"]
print(d["systemMessage"])' 2>/dev/null
}

expect_silent() { # NAME OUTPUT
	if [ -z "$2" ] && [ ! -s "$TMP/stderr" ]; then pass; else fail "$1: expected no output" "$2$(cat "$TMP/stderr")"; fi
}

expect_message() { # NAME OUTPUT WANT...
	name=$1 out=$2
	shift 2
	msg=$(message "$out")
	[ -n "$msg" ] || { fail "$name: expected SessionStart hook JSON" "$out"; return; }
	for want in "$@"; do
		case "$msg" in
		*"$want"*) ;;
		*) fail "$name: message lacks \"$want\"" "$msg"; return ;;
		esac
	done
	pass
}

expect_lacks() { # NAME OUTPUT UNWANTED
	case "$(message "$2")" in
	*"$3"*) fail "$1: message should not mention \"$3\"" "$(message "$2")" ;;
	*) pass ;;
	esac
}

guide_block() { printf '# Project\n<!-- gooze:begin %s -->\nold guide\n<!-- gooze:end -->\n' "$1"; }

OK="$BIN/gooze:$BIN/goozels-new:$SYS"
P=$TMP/proj

# --- SessionStart: tools -------------------------------------------------------

mkdir -p "$TMP/not-go"
expect_silent "non-Go project, no tools" "$(preflight "$TMP/not-go" "$BIN/none:$SYS")"

go_project "$P"
expect_silent "Go project, tools present, no guide" "$(preflight "$P" "$OK")"

out=$(preflight "$P" "$BIN/goozels-new:$SYS")
expect_message "missing gooze" "$out" "gooze is not installed" "go install gooze.dev/pkg/gooze@latest"
expect_lacks "missing gooze only" "$out" "goozels"

out=$(preflight "$P" "$BIN/gooze:$BIN/goozels-old:$SYS")
expect_message "old goozels" "$out" "goozels is missing or too old" "go install gooze.dev/pkg/goozels/cmd/goozels@latest"
expect_lacks "old goozels only" "$out" "gooze is not installed"

out=$(preflight "$P" "$BIN/gooze:$SYS")
expect_message "missing goozels" "$out" "goozels is missing or too old"

out=$(preflight "$P" "$BIN/none:$SYS")
expect_message "both missing" "$out" "gooze is not installed" "goozels is missing or too old" " && "

# --- SessionStart: guide versions ---------------------------------------------

go_project "$P"
guide_block "guide=1 gooze=v1.1.1" >"$P/CLAUDE.md"
expect_silent "guide up to date" "$(preflight "$P" "$OK")"

guide_block "guide=0 gooze=v1.1.1" >"$P/CLAUDE.md"
expect_message "older guide" "$(preflight "$P" "$OK")" "CLAUDE.md is outdated" "guide 0, current 1" "/gooze:init"

guide_block "" >"$P/CLAUDE.md"
expect_message "unversioned guide" "$(preflight "$P" "$OK")" "CLAUDE.md is outdated" "unversioned"

rm "$P/CLAUDE.md"
guide_block "guide=1 gooze=v1.0.0" >"$P/AGENTS.md"
expect_message "older gooze in AGENTS.md" "$(preflight "$P" "$OK")" "AGENTS.md was written for gooze v1.0.0" "v1.1.1 is installed"

guide_block "guide=1 gooze=v1.0.0" >"$P/AGENTS.md"
expect_silent "gooze not installed: no version comparison" "$(preflight "$P" "$BIN/goozels-new:$SYS" | grep -o 'written for' || true)"

guide_block "guide=1 gooze=v1.1.1" >"$P/AGENTS.md"
guide_block "guide=0 gooze=v1.1.1" >"$P/CLAUDE.md"
out=$(preflight "$P" "$OK")
expect_message "only the outdated file is named" "$out" "CLAUDE.md is outdated"
expect_lacks "up-to-date AGENTS.md not named" "$out" "AGENTS.md"

guide_block "guide=0 gooze=v1.1.1" >"$P/AGENTS.md"
expect_message "both files outdated" "$(preflight "$P" "$OK")" "CLAUDE.md is outdated" "AGENTS.md is outdated"

rm "$P/AGENTS.md"
mkdir -p "$P/internal/pkg"
expect_message "run from a subdirectory" "$(preflight "$P/internal/pkg" "$OK")" "CLAUDE.md is outdated"

guide_block "guide=1 gooze=v1.1.1" >"$P/CLAUDE.md"
expect_message "newer plugin guide" "$(preflight "$P" "$OK" "$(plugin_root 2)")" "guide 1, current 2"

guide_block "guide=0 gooze=v1.1.1" >"$P/CLAUDE.md"
expect_silent "plugin without guide.md" "$(preflight "$P" "$OK" "$(plugin_root "")")"

# --- PostToolUse guard ---------------------------------------------------------

guard=$(python3 -c 'import json,sys
h=json.load(open(sys.argv[1]))["hooks"]["PostToolUse"][0]["hooks"][0]
assert h["command"] == "sh" and h["args"][0] == "-c", h
print(h["args"][1])' "$HOOKS_JSON") || fail "PostToolUse hook is not an sh -c command" "$guard"

payload='{"tool_input":{"file_path":"/p/x.go"}}'

rm -f "$TMP/hook-args" "$TMP/hook-stdin"
out=$(printf '%s' "$payload" | env PATH="$BIN/goozels-new:$SYS" sh -c "$guard")
code=$?
if [ "$code" = 0 ] && [ "$(cat "$TMP/hook-args" 2>/dev/null)" = "hook claude" ] && [ "$(cat "$TMP/hook-stdin" 2>/dev/null)" = "$payload" ] && [ -n "$out" ]; then
	pass
else
	fail "new goozels: guard runs 'goozels hook claude' with the payload" "exit=$code args=$(cat "$TMP/hook-args" 2>/dev/null) stdin=$(cat "$TMP/hook-stdin" 2>/dev/null) out=$out"
fi

rm -f "$TMP/old-hook-called"
out=$(printf '%s' "$payload" | env PATH="$BIN/goozels-old:$SYS" sh -c "$guard" 2>&1)
code=$?
if [ "$code" = 0 ] && [ -z "$out" ] && [ ! -e "$TMP/old-hook-called" ]; then pass; else fail "old goozels: guard skips the hook" "exit=$code out=$out called=$([ -e "$TMP/old-hook-called" ] && echo yes)"; fi

out=$(printf '%s' "$payload" | env PATH="$BIN/none:$SYS" sh -c "$guard" 2>&1)
code=$?
if [ "$code" = 0 ] && [ -z "$out" ]; then pass; else fail "no goozels: guard is silent" "exit=$code out=$out"; fi

# --- CI score gate in the ci-setup skill -----------------------------------------
# The gate step parses the score line of `gooze report view`. gooze v1.2.0
# appends a breakdown to it; the documented sed must read both forms.

for f in "$ROOT"/skills/ci-setup/github-actions.md "$ROOT"/skills/ci-setup/gitlab-ci.md; do
	expr=$(sed -n "s/.*sed -n '\(s\/^Mutation score:[^']*\)'.*/\1/p" "$f" | head -n 1)
	if [ -z "$expr" ]; then
		fail "$(basename "$f"): no score gate sed expression found"
		continue
	fi
	for line in "Mutation score: 87.50%" "Mutation score: 87.50% (14 killed, 2 survived)"; do
		got=$(printf 'Survivors (2):\n%s\n' "$line" | sed -n "$expr" | tail -n 1)
		if [ "$got" = "87.50" ]; then pass; else fail "$(basename "$f"): gate reads \"$line\" as \"$got\", want 87.50"; fi
	done
done

# --- result ------------------------------------------------------------------

printf '%d passed, %d failed\n' "$passes" "$fails"
[ "$fails" -gt 100 ] && fails=100
exit "$fails"
