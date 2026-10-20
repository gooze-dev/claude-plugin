# gooze reference

Verified against gooze v1.1.1. Full docs: <https://gooze.dev/docs>.

## Mutagens

Names accepted by `//gooze:ignore`:

| Mutagen | What it mutates |
|---|---|
| `arithmetic` | arithmetic operators (`+`, `-`, `*`, `/`, `%`) |
| `boolean` | boolean literals (`true` ↔ `false`) |
| `numbers` | numeric literals (e.g. `5` → `0`, `5` → `1`) |
| `comparison` | comparison operators (`<`, `>`, `<=`, `>=`, `==`, `!=`) |
| `logical` | logical operators (`&&`, `\|\|`) |
| `unary` | unary operators (`-`, `+`, `!`, `^`) |
| `branch` | branch and conditional expressions (`if`, `for`, `switch` conditions) |
| `statement` | deletes statements (assignments, expressions, `defer`, `go`, send) |
| `loop` | loops (boundary conditions, body removal, `break`/`continue` removal) |

## Commands

| Command | Purpose |
|---|---|
| `gooze run [paths...]` | run mutation testing on Go path patterns (`./...`, `./pkg/foo/...`) |
| `gooze run --estimate [paths...]` | list files and mutation counts without running tests |
| `gooze report view [paths...]` | per-file scores and survivors (v1.2.0+; filter by path, e.g. `./internal/foo/...`) |
| `gooze report view --all [paths...]` | every mutation with its status and diff |
| `gooze report merge` | merge sharded reports (`shard_N/`) into one directory |
| `gooze report push <ref>` / `pull <ref>` | store or fetch reports in an OCI registry (CI baselines) |
| `gooze config init` | write a default `gooze.yaml` |
| `gooze version` | print the version |

There is no `gooze list` or top-level `gooze view`. <!-- lint-ignore: names commands that do not exist -->

### `gooze run` flags

| Flag | Meaning |
|---|---|
| `-p, --parallel N` | parallel workers |
| `-s, --shard I/N` | run shard `I` of `N` (e.g. `0/4`), for CI |
| `--estimate` | preview only |
| `--mutation-timeout SEC` | per-mutation test timeout (default 120) |
| `--coverage-profile FILE` | Go coverage profile; mutations on uncovered lines become `not_covered` without running tests |

Global: `-x, --exclude REGEX` (repeatable), `-o, --output DIR` (default
`.gooze-reports`), `--no-cache` (re-test everything), `-v, --verbose`.

## Statuses and score

Each mutation ends as `killed`, `survived`, `skipped`, `timeout`, `error` or
`not_covered`. Score = killed ÷ (all mutations except `error`).

## Report files

`.gooze-reports/` holds one YAML file per mutation (named by a hash) plus
`_index.yaml` with totals. Cached results for a file are invalidated when its
source or test file changes, a mutagen version changes, or the file is deleted.

## gooze.yaml keys

`version`, `output`, `no-cache`, `paths.exclude`, `run.parallel`,
`run.mutation_timeout`, `run.coverage_profile`, `log.filename`, `log.level`,
`log.verbose`, `log.max_size`, `log.max_backups`, `log.max_age`, `log.compress`.
Environment variables use the `GOOZE_` prefix (e.g. `GOOZE_LOG_MAX_SIZE`).

## goozels

| Command | Purpose |
|---|---|
| `goozels check [-workdir DIR] [-max N] FILE...` | gooze diagnostics as `file:line:col: severity: message`; a `_test.go` file also lists the survivors of the sources it tests |
| `goozels hook claude` / `goozels hook codex` | post-edit hooks (read a PostToolUse payload on stdin) |
| `goozels version` | prints `goozels <version>`; hooks use it to detect support |

`check` finds the workspace root by walking up to `.gooze-reports` (else
`go.mod`). Exit status: 0 no errors, 1 an `error:` diagnostic was printed or a
file could not be read, 2 usage error.

Line formats:

- `gooze: score 87.50% — 14 killed, 2 survived` (top of file)
- ``gooze: surviving comparison mutant — tests still pass with `if n < lo {` → `if n <= lo {` ``
- `gooze: 6 surviving mutants (comparison ×5, numbers) — …` (several on one line, at most 5 variants shown)
- ``gooze: boolean mutant not covered by any test — `return false` → `return true` ``
- `gooze: results are from before calc.go changed; score then 87.50%; rerun: gooze run ./calc` (no line markers while stale)
- `gooze: tests changed since the last run (calc_test.go); score then 87.50%; rerun: gooze run ./calc`
- `no gooze results for new.go yet; run: gooze run .` (stderr)
- `… 34 more; run goozels check internal/domain/workflow.go` (when `-max` cuts the list)
