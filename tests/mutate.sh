#!/bin/sh
# Mutation check for the hook scripts, in the spirit of gooze: apply one small
# change at a time to a copy of a script and run tests/run.sh against the copy.
# Every mutant must make at least one test fail ("killed"); a surviving mutant
# means a behaviour no test pins down.
#
# Usage: sh tests/mutate.sh    (exit status is the number of surviving mutants)

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
killed=0
survived=0

# mutant NAME FILE FROM TO: replace the first FROM (a fixed string) with TO.
mutant() {
	name=$1 file=$2 from=$3 to=$4
	copy=$TMP/$(basename "$file")

	if ! python3 - "$file" "$copy" "$from" "$to" <<'EOF'
import sys
src, dst, old, new = sys.argv[1:]
text = open(src).read()
if old not in text:
    sys.exit(1)
open(dst, "w").write(text.replace(old, new, 1))
EOF
	then
		printf 'STALE  %s (text not found; update tests/mutate.sh)\n' "$name"
		survived=$((survived + 1))
		return
	fi

	case "$file" in
	*.json) env HOOKS_JSON="$copy" sh "$ROOT/tests/run.sh" >/dev/null 2>&1 ;;
	*) env SESSION_START="$copy" sh "$ROOT/tests/run.sh" >/dev/null 2>&1 ;;
	esac

	if [ $? -ne 0 ]; then
		killed=$((killed + 1))
	else
		survived=$((survived + 1))
		printf 'SURVIVED  %s\n' "$name"
	fi
}

S=$ROOT/scripts/session-start.sh
H=$ROOT/hooks/hooks.json

# Control: unmodified copies must pass, or every "kill" below is meaningless.
cp "$S" "$TMP/control.sh"
cp "$H" "$TMP/control.json"
if ! env SESSION_START="$TMP/control.sh" HOOKS_JSON="$TMP/control.json" sh "$ROOT/tests/run.sh" >/dev/null 2>&1; then
	echo "control run failed: tests/run.sh doesn't pass on unmodified copies"
	exit 1
fi

mutant "non-Go projects also get checked" "$S" '[ "$dir" = "/" ] && exit 0' '[ "$dir" = "/" ] && break'
mutant "missing gooze not detected" "$S" 'if ! command -v gooze' 'if command -v gooze'
mutant "any goozels counts as new" "$S" 'goozels*) ;;' '*) ;;'
mutant "goozels check inverted" "$S" 'goozels*) ;;' 'goozels*) notes=x ;;'
mutant "silent exit when there is something to say" "$S" '[ -z "$notes" ] && exit 0' '[ -n "$notes" ] && exit 0'
mutant "AGENTS.md ignored" "$S" '"$dir/CLAUDE.md" "$dir/AGENTS.md"' '"$dir/CLAUDE.md"'
mutant "CLAUDE.md ignored" "$S" '"$dir/CLAUDE.md" "$dir/AGENTS.md"' '"$dir/AGENTS.md"'
mutant "guide compare off by one" "$S" '-lt "$current_guide"' '-le "$current_guide"'
mutant "guide compare reversed" "$S" '-lt "$current_guide"' '-gt "$current_guide"'
mutant "unversioned guide counts as current" "$S" '"${guide:-0}"' '"${guide:-1}"'
mutant "gooze version read from stdout only" "$S" '</dev/null 2>&1 | semver' '</dev/null 2>/dev/null | semver'
mutant "gooze version mismatch inverted" "$S" '"$recorded_gooze" != "$installed_gooze"' '"$recorded_gooze" = "$installed_gooze"'
mutant "version compare without gooze installed" "$S" '[ -n "$installed_gooze" ] &&' 'true &&'
mutant "file name dropped from the notice" "$S" 'The gooze guide in $name is outdated' 'The gooze guide is outdated'
mutant "install command dropped" "$S" 'fixes="go install gooze.dev/pkg/gooze@latest"' 'fixes=""'
mutant "hook: any goozels runs the hook" "$H" 'in goozels*) exec' 'in *) exec'
mutant "hook: wrong agent name" "$H" 'exec goozels hook claude' 'exec goozels hook codex'
mutant "hook: failure exit when skipped" "$H" 'esac; exit 0' 'esac; exit 1'

printf '%d killed, %d survived\n' "$killed" "$survived"
exit "$survived"
