#!/bin/sh
# SessionStart preflight for the gooze plugin. In a Go project, it checks that
# the tools the plugin relies on are installed and that the gooze guide written
# by /gooze:init is current. When something needs attention it tells both the
# user (systemMessage) and Claude (additionalContext) how to fix it. It prints nothing when everything is in place or the project
# isn't Go, and never fails the session.

# Only Go projects: a go.mod in the session directory or one of its parents.
dir=$(pwd)
while [ ! -f "$dir/go.mod" ]; do
	[ "$dir" = "/" ] && exit 0
	dir=$(dirname "$dir")
done

notes=""
fixes=""

if ! command -v gooze >/dev/null 2>&1; then
	notes="gooze is not installed, so mutation tests can't run."
	fixes="go install gooze.dev/pkg/gooze@latest"
fi

# goozels releases before the agent hooks pass unknown arguments to gopls, so
# "goozels version" only identifies itself on versions that support the hook.
case "$(goozels version </dev/null 2>/dev/null)" in
goozels*) ;;
*)
	notes="${notes:+$notes }goozels is missing or too old, so gooze results don't appear after edits."
	fixes="${fixes:+$fixes && }go install gooze.dev/pkg/goozels/cmd/goozels@latest"
	;;
esac

# An outdated gooze guide in CLAUDE.md or AGENTS.md (written by /gooze:init):
# its opening marker records the guide version and the gooze version it was
# written for, e.g. <!-- gooze:begin guide=1 gooze=v1.2.0 -->. Projects without
# the guide get no notice.
semver() { grep -o 'v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' | head -n 1; }
marker_field() { sed -n "s/.*<!-- gooze:begin.* $1=\([^ ]*\).*-->.*/\1/p" | head -n 1; }

current_guide=$(marker_field guide 2>/dev/null <"${CLAUDE_PLUGIN_ROOT:-.}/skills/init/guide.md")
installed_gooze=$(gooze version </dev/null 2>&1 | semver)

for file in "$dir/CLAUDE.md" "$dir/AGENTS.md"; do
	grep -q '<!-- gooze:begin' "$file" 2>/dev/null || continue

	guide=$(marker_field guide <"$file")
	recorded_gooze=$(marker_field gooze <"$file")
	name=$(basename "$file")

	if [ -n "$current_guide" ] && [ "${guide:-0}" -lt "$current_guide" ] 2>/dev/null; then
		notes="${notes:+$notes }The gooze guide in $name is outdated (guide ${guide:-unversioned}, current $current_guide)."
		fixes="${fixes:+$fixes, then }run /gooze:init to update it"
	elif [ -n "$installed_gooze" ] && [ "$recorded_gooze" != "$installed_gooze" ]; then
		notes="${notes:+$notes }The gooze guide in $name was written for gooze ${recorded_gooze:-(unknown)}, but $installed_gooze is installed."
		fixes="${fixes:+$fixes, then }run /gooze:init to update it"
	fi
done

[ -z "$notes" ] && exit 0

note="gooze plugin: $notes Fix: $fixes."
printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$note" "$note"
