---
name: init
description: Set up a Go project for gooze mutation testing, asking before each change - create gooze.yaml, add or update a versioned gooze guide block in CLAUDE.md / AGENTS.md, allow gooze commands in .claude/settings.json, then point to CI setup.
when_to_use: Run when the user types /gooze:init, or re-runs it to update an outdated gooze guide block.
disable-model-invocation: true
allowed-tools: Read Glob Grep Bash(gooze version)
---

# Set up this project for gooze

Four steps. For each: check the current state, say what you'd change, show
the exact content, and change it **only after the user agrees**. A "no" skips
that step; continue with the next. Never touch anything else in the files you
edit. Don't commit.

## 0. Versions

- **Guide version**: the `guide=N` in the first line of [guide.md](guide.md)
  (the source of truth; it also holds the recommended gooze version).
- **gooze version**: run `gooze version` and take the leading `vX.Y.Z` from the
  `tool version` line (`v1.1.1-0.2026...+dirty` → `v1.1.1`; tell the user if it
  is a development build). If gooze isn't installed, use the `gooze=` value in
  guide.md's marker, say so, and suggest
  `go install gooze.dev/pkg/gooze@<that version>`.

## 1. gooze.yaml

Glob for `gooze.yaml` in the repo root. If it exists, leave it alone (mention
`goozels check gooze.yaml` validates it). If not, offer `gooze config init`: it
writes `./gooze.yaml` with the defaults (`version: 1`, `output: .gooze-reports`,
`paths.exclude: []`, `run.parallel: 1`, `run.mutation_timeout: 120`,
`run.coverage_profile: ""`, `no-cache: false`, `log.*`) and refuses to
overwrite an existing file. Excludes given as flags are written into it:
`gooze config init -x mocks/ -x '_gen\.go$'`. Suggest excludes for
directories the repo actually has (mocks, generated code), if any.

## 2. Guide block in CLAUDE.md / AGENTS.md

The block is the whole content of [guide.md](guide.md), copied verbatim,
except `gooze=` in the first line, set to the version from step 0. Marker
grammar (one line each, exact):

```
<!-- gooze:begin guide=<N> gooze=<vX.Y.Z> -->
...
<!-- gooze:end -->
```

**Which file.** Glob for `CLAUDE.md` and `AGENTS.md` in the repo root.
- Only one exists: that one.
- `CLAUDE.md` is only an import of AGENTS.md (its content is just `@AGENTS.md`,
  maybe with blank lines or a heading): `AGENTS.md` only.
- Both have their own content: propose both, and ask if the user wants just one.
- Neither: ask before creating `CLAUDE.md` containing only the block; mention
  `AGENTS.md` instead (or as well) if the team also uses Codex or opencode.

**Existing block.** Grep the chosen file(s) for `<!-- gooze:begin`.
- None: append the block at the end, after a blank line.
- Found: parse `guide=` and `gooze=` from its marker line. A marker without
  them (e.g. plain `<!-- gooze:begin -->`) counts as outdated.
  - Same guide N and same gooze version: say the guide is up to date and
    change nothing.
  - Older N, missing versions, or a different gooze version: say which
    differs (old → new), summarize the text changes, and offer to **replace
    everything from the begin line through `<!-- gooze:end -->`** with the new
    block, in place. Never add a second block. If the end marker is missing,
    show the user the span you'd replace and ask.

## 3. Permissions in .claude/settings.json

Explain: without allow rules, each gooze command (e.g. during `/code-review`
or the mutation-testing loop) stops at a permission prompt; a plugin can't
pre-approve commands for the project. Offer to add to `permissions.allow`:

```json
"Bash(gooze run *)",
"Bash(gooze report view*)",
"Bash(goozels check *)"
```

Read `.claude/settings.json` if it exists and merge: keep every existing key
and rule, add only missing ones, keep it valid JSON. If it doesn't exist, ask,
then create it with just `{"permissions": {"allow": [...]}}`. Mention
`.claude/settings.local.json` if the user wants the rules only for themselves
(settings.json is usually committed and shared).

## 4. CI

Glob for `Makefile`, `.github/workflows/*.yml`, `.github/workflows/*.yaml`,
`.gitlab-ci.yml`, `Taskfile.yml`, `justfile`. If any exists, suggest
`/gooze:ci-setup` to add gooze to them (pinned to the same gooze version as
the guide marker). If none, skip; don't propose creating CI files.

End with a short summary of what changed and what was skipped.
