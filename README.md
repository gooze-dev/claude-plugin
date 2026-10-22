# gooze for Claude Code

A Claude Code plugin for [gooze](https://github.com/gooze-dev/gooze), the Go
mutation testing tool.

| Part | What it does |
|---|---|
| **`/gooze:init`** | Sets a Go project up for gooze, asking before each change: writes `gooze.yaml`, adds a short gooze guide to `CLAUDE.md` and/or `AGENTS.md` (including a code-review rule), and allows the gooze commands in `.claude/settings.json`. |
| **`/gooze:mutation-testing`** | The gooze loop: scope and run `gooze run` in parallel, read the score and surviving mutants, write tests that kill them, rerun to confirm. Knows when a mutant can't be killed and how to use `//gooze:ignore` narrowly. Claude loads it on its own when you ask about mutation testing. |
| **`/gooze:ci-setup`** | Recommends adding gooze to the build and CI files the repo **already has** (Makefile, GitHub Actions, GitLab CI, Google Cloud Build, Taskfile, justfile, …), adapted to their conventions, and applies it only after you agree. It never creates a new CI file. |
| **Post-edit hook** | After Claude edits a Go file or `gooze.yaml`, it gets that file's gooze results: the score, each surviving mutant with the change your tests missed (original → mutated), mistyped `//gooze:ignore` mutagens and `gooze.yaml` errors. Editing a test shows the survivors of the code it tests. It says when results are stale and gives the rerun command. Needs [goozels](https://github.com/gooze-dev/goozels). |
| **Session check** | In Go projects, tells you once at session start when `gooze` or `goozels` is missing, too old, or behind the latest release, or when the guide written by `/gooze:init` is outdated, with the fix. It reads the latest-release cache that gooze and goozels keep, so it never waits on the network. Silent otherwise. |

It works alongside the official `gopls-lsp` plugin; keep that on for Go code
intelligence.

## Install

In Claude Code:

```text
/plugin marketplace add gooze-dev/claude-plugin
/plugin install gooze@gooze
```

Then install the tools (on the `PATH` of the shell you start `claude` from):

```bash
go install gooze.dev/pkg/gooze@latest                # required (v1.3.0+ for --diff, --run, --mutagens and thresholds; v1.2.0 works with fallbacks)
go install gooze.dev/pkg/goozels/cmd/goozels@latest  # for the post-edit hook (v0.2.0+; v0.3.0 knows gooze v1.3.0)
```

gooze needs Go 1.27.3 to build. On an older Go, prefix the commands with
`GOTOOLCHAIN=auto` so Go fetches the toolchain for you; your project keeps its
own Go version.

Then, in your project, run `/gooze:init` once.

To get new plugin versions automatically, open `/plugin`, go to
**Marketplaces**, select `gooze` and choose **Enable auto-update**. Otherwise
run `/plugin marketplace update gooze`.

## Use it

Ask in plain words, for example:

- *"Run gooze on `./internal/domain/...` and kill the surviving mutants in
  `ignore.go` without changing production code."*
- *"Which files in this package have the lowest mutation score?"*
- *"Are any of the surviving mutants in `parser.go` equivalent? Suppress only
  those."*
- *"Add mutation testing to our CI."*

## Code review

Claude Code's built-in `/code-review` follows your `CLAUDE.md`, so the
code-review rule that `/gooze:init` adds makes reviews run gooze on the changed
packages and report surviving mutants as test gaps. Reviews need the gooze
commands pre-approved, which `/gooze:init` also offers. Claude Code applies a
project's allow rules only once you've trusted the folder, so a headless run in
a fresh checkout (`claude -p "/code-review"` in CI) needs them passed with
`--allowedTools "Bash(gooze run *) Bash(goozels check *)"` instead. A plugin can't add a
reviewer to the built-in review, and the managed Code Review service doesn't
run code, so for pull requests run gooze in CI (`/gooze:ci-setup`) and give the
reviewer its report.

## Develop

```bash
claude --plugin-dir .          # load this checkout for one session
claude plugin validate .       # check the manifest and marketplace
sh tests/run.sh                # tests for the hook scripts
sh tests/mutate.sh             # every deliberate break of a hook script must fail a test
python3 tests/lint_commands.py # skills may only use real gooze/goozels commands
```

CI runs all of these on every push. Change the hook scripts test-first: add a
failing case to `tests/run.sh`, then fix the script, then add a mutant to
`tests/mutate.sh` if a new branch could break unnoticed.

Skill behaviour has evals in `evals/`, one case per directory, run with
`claude plugin eval` (Claude Code 2.1.269+). They make real model calls on
your account, so they aren't part of CI; run them when a skill's text
changes:

```bash
claude plugin eval . --scaffold --allow-tools Edit Write --max-cost-usd 5
```

They check that the mutation-testing skill triggers on a test-quality
question and not on an unrelated one, that it kills a boundary survivor with
a test without touching production code, and that it labels an equivalent
mutant instead of inventing a test.

Bump `version` in `.claude-plugin/plugin.json` on every release; users only
receive changes when it changes. Bump `guide=` in `skills/init/guide.md` when
the guide text changes, so projects are told to rerun `/gooze:init`.

## License

[MIT](LICENSE)
