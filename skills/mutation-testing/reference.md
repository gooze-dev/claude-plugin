# gooze reference

Verified against gooze v1.2.0. Full docs: <https://gooze.dev/docs>.

## Mutagens

Names accepted by `//gooze:ignore` and `--mutagens`. A run uses every
mutagen but `branch`, `statement` and `loop`, which run only when selected
with `--mutagens` or `run.mutagens`. Releases before `bitwise`, `increment`
and `assignment` existed reject those names; `gooze run --help` lists the
names a release accepts under `--mutagens`.

| Mutagen | What it mutates |
|---|---|
| `arithmetic` | arithmetic operators (`+`, `-`, `*`, `/`, `%`) |
| `boolean` | boolean literals (`true` ↔ `false`) |
| `numbers` | numeric literals (e.g. `5` → `0`, `5` → `1`) |
| `comparison` | comparison operators (`<`, `>`, `<=`, `>=`, `==`, `!=`) |
| `logical` | logical operators (`&&`, `\|\|`) |
| `unary` | unary operators (`-`, `+`, `!`, `^`) |
| `bitwise` | bitwise operators (`&` ↔ `\|`, `^` → `&`, `&^` → `&`, `<<` ↔ `>>`) |
| `increment` | `x++` ↔ `x--`, not in a `for` loop's post statement |
| `assignment` | compound assignments (`+=` ↔ `-=`, `*=` ↔ `/=`, `&=` ↔ `\|=`, `<<=` ↔ `>>=`, ...), and `x op= y` → `x = y` |
| `branch` | off by default: inverts and forces `if`/`for` conditions, removes `if`/`else` blocks and `switch` case bodies |
| `statement` | off by default: deletes statements (assignments, calls, `defer`, `go`, sends); keeps `:=` declarations |
| `loop` | off by default: loop boundaries, body removal, `break`/`continue` removal, recursive calls |

`branch`, `statement` and `loop` also make mutants that don't compile
(status `error`, left out of the score) and a few that time out.

## Commands

| Command | Purpose |
|---|---|
| `gooze run [paths...]` | run mutation testing on Go path patterns (`./...`, `./pkg/foo/...`) |
| `gooze run --estimate [paths...]` | list files and mutation counts without running tests |
| `gooze report view [paths...]` | per-file scores and survivors (v1.2.0+; filter by path, e.g. `./internal/foo/...`) |
| `gooze report view --all [paths...]` | every mutation with its status and diff |
| `gooze report merge` | merge sharded reports (`shard_N/`) into one directory; also folds in a narrowed run (`run/`) |
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
| `--diff REF` | only lines changed since the merge base of `REF` and HEAD (needs git) |
| `--run REGEX` | only functions matching, as for `go test -run` (`Name`, `Type.Name`); not with `--shard` |
| `--mutagens LIST` | only these mutagens, comma-separated |
| `--workspace MODE` | how mutants are built: `overlay` (default) or `deep-copy`; see [killing-survivors.md](killing-survivors.md#tests-that-dont-see-the-mutant) |

Older releases lack `--diff`, `--run` and `--mutagens`, and with them the
`run/` directory, the report `scope` and the `no-update-check`, `run.diff`
and `run.mutagens` keys: check that `gooze run --help` lists the flags. Releases
without `--workspace` always test in a copy of the project, like `deep-copy`. A run
with any of them writes to `<output>/run/` and scores only its selection;
`gooze report merge` folds it into the main reports.

Global: `-x, --exclude REGEX` (repeatable), `-o, --output DIR` (default
`.gooze-reports`), `--no-cache` (re-test everything), `-v, --verbose`.

## Statuses and score

Each mutation ends as `killed`, `survived`, `skipped`, `timeout`, `error` or
`not_covered`. Score = killed ÷ (all mutations except `error`).

## Thresholds and exit codes

`gooze run`, `gooze report view` and `gooze report merge` take
`--threshold-total`, `--threshold-average` and `--threshold-file` (percent,
`0` = off; keys `threshold.total|average|file`, env `GOOZE_THRESHOLD_TOTAL`,
...): the score of all mutations, the mean of per-file scores, and the
minimum for every file. Files with no scored mutations are ignored. A
`gooze run --diff REF` run uses `--threshold-diff-total|average|file`
(`threshold.diff.*`) instead, scored on the changed lines. A shard
(`-s I/N`, N > 1) checks none; `gooze report merge` does. Older releases lack
them: check that `gooze run --help` lists `--threshold-total`.

| Exit | Meaning |
|---|---|
| 0 | done, every threshold met (or none set) |
| 1 | unexpected failure (I/O, reports, internal) |
| 2 | usage or config error |
| 3 | done, reports written, but a score is below a threshold (`Error: ... is below threshold.X N%` on stderr) |
| 4 | git or diff error |
| 5 | OCI registry error (`report push` / `pull`) |
| 6 | no reports to view or merge |
| 130 | interrupted |

## Report files

`.gooze-reports/` holds one YAML file per mutation (named by a hash) plus
`_index.yaml` with totals. Cached results for a file are invalidated when its
source or test file changes, a mutagen version changes, or the file is deleted.
Reports record the mutation's `line`, and a `scope` when a run was narrowed;
a file holding partial results is re-tested in full by the next full run. `run/` holds the last narrowed run until `gooze report merge`.

## gooze.yaml keys

`version`, `output`, `no-cache`, `paths.exclude`, `run.parallel`,
`run.mutation_timeout`, `run.coverage_profile`, `log.filename`, `log.level`,
`log.verbose`, `log.max_size`, `log.max_backups`, `log.max_age`, `log.compress`,
`no-update-check`, `run.diff`, `run.mutagens`, `run.workspace`, `threshold.total`,
`threshold.average`, `threshold.file`, `threshold.diff.total`,
`threshold.diff.average` and `threshold.diff.file` (`--run` has no key, like
`go test -run`). Environment variables use the `GOOZE_` prefix (e.g. `GOOZE_LOG_MAX_SIZE`, `GOOZE_RUN_MUTAGENS`).

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
