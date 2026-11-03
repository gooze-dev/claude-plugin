# gooze reference

Verified against gooze v1.4.1 and main (v1.5.0+ features are marked). Full docs: <https://gooze.dev/docs>.

## Mutagens

Names accepted by `//gooze:ignore` and `--mutagens`. A run uses every
mutagen but `branch`, `statement` and `loop`, which run only when selected
with `--mutagens` or `run.mutagens`. Releases before v1.3.0 reject `bitwise`,
`increment`, `assignment`, `branch`, `statement` and `loop`; `gooze run --help` lists the
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
| `gooze report view --by-line [paths...]` | the survivors once per line of a file, changes folded; with `--format github` it groups the summary after the annotations (v1.5.0+; not with `--all`, `--format sarif` or `--format codeclimate`/`gitlab`, exit 2) |
| `gooze report merge` | merge sharded reports (`shard_N/`) into one directory; also folds in a narrowed run (`run/`) |
| `gooze report push <ref>` / `pull <ref>` | store or fetch reports in an OCI registry (CI baselines) |
| `gooze config init` | write a default `gooze.yaml` |
| `gooze config show` | every config key with its effective value, its source (flag, env, `gooze.yaml` or default) and env var (v1.5.0+) |
| `gooze config schema` | the JSON Schema of `gooze.yaml`, for editors (v1.5.0+) |
| `gooze version` | print the version (`gooze --version` too, v1.5.0+) |

Installed as a Go tool (`go get -tool gooze.dev/pkg/gooze@v1.4.1`, which
adds a `tool` line to `go.mod`), every command runs as `go tool gooze ...`
at the version `go.mod` pins. That raises the module's `go` line to gooze's
(1.27.3) and adds its dependencies (about 55) as indirect requires.

There is no `gooze list` or top-level `gooze view`. <!-- lint-ignore: names commands that do not exist -->

### `gooze run` flags

| Flag | Meaning |
|---|---|
| `-p, --parallel N` | parallel workers |
| `-s, --shard I/N` | run shard `I` of `N` (e.g. `0/4`), for CI |
| `--estimate` | preview only |
| `--mutation-timeout SEC` | per-mutation test timeout (default 120) |
| `--coverage-profile FILE` | Go coverage profile; mutations on uncovered lines become `not_covered` without running tests |
| `--diff REF` | only lines changed since the merge base of `REF` and HEAD (needs git), plus every line of `x.go` when `x_test.go` changed |
| `--run REGEX` | only functions matching, as for `go test -run` (`Name`, `Type.Name`); not with `--shard` |
| `--mutagens LIST` | only these mutagens, comma-separated |
| `--workspace MODE` | how mutants are built: `overlay` (default) or `deep-copy`; see [killing-survivors.md](killing-survivors.md#tests-that-dont-see-the-mutant) |

Releases before v1.3.0 lack `--diff`, `--run` and `--mutagens`, and with them
the `run/` directory, the report `scope` and the `no-update-check`, `run.diff`
and `run.mutagens` keys: check that `gooze run --help` lists the flags. Releases
before v1.3.0 also lack `--workspace` and always test in a copy of the
project, like `deep-copy`. A run
with any of them writes to `<output>/run/` and scores only its selection;
`gooze report merge` folds it into the main reports.

Global: `-x, --exclude REGEX` (repeatable), `-o, --output DIR` (default
`.gooze-reports`), `--no-cache` (re-test everything), `--no-update-check`,
`-v, --verbose`, `--log-output FILE`, `--log-level debug|info|warn|error`
(v1.5.0+, key `log.level`; `--verbose` overrides it).

## Statuses and score

Each mutation ends as `killed`, `survived`, `skipped`, `timeout`, `error` or
`not_covered`. Score = killed ÷ (all mutations except `error`).
`gooze report view` (v1.5.0+) has `TIMEOUT` and `ERROR` columns and lists
mutants that did not build under `Build errors (N):`; `gooze run` prints no
diff for them. A build error is no test gap: it isn't scored, needs no test,
and the `github`, `sarif` and `codeclimate` formats skip it.

## Thresholds and exit codes

`gooze run`, `gooze report view` and `gooze report merge` take
`--threshold-total`, `--threshold-average` and `--threshold-file` (percent,
`0` = off; keys `threshold.total|average|file`, env `GOOZE_THRESHOLD_TOTAL`,
...): the score of all mutations, the mean of per-file scores, and the
minimum for every file. Files with no scored mutations are ignored. A
`gooze run --diff REF` run uses `--threshold-diff-total|average|file`
(`threshold.diff.*`) instead, scored on the changed lines, and so does
`gooze report view -o .gooze-reports/run` of its reports (v1.4.0+; of its
merged shards v1.4.1+). A shard
(`-s I/N`, N > 1) checks none; `gooze report merge` does (for `--diff`
shards, `-o .gooze-reports/run`, the diff ones since v1.5.0). Releases before
v1.3.0 lack them: check that `gooze run --help` lists `--threshold-total`.

`--threshold-max-survivors N` (`threshold.max_survivors`, env
`GOOZE_THRESHOLD_MAX_SURVIVORS`; a count, `0` = off) fails the same commands
when more than N mutants survive. Only `survived` counts; a `--diff` run
counts the survivors on its changed lines. v1.4.0+: check
that `gooze run --help` lists it.

`gooze run --fail-fast POLICY` (`run.fail_fast`, env `GOOZE_RUN_FAIL_FAST`,
default `off`) stops before every mutant is tested: `gate` once a threshold
can no longer be met (untested mutants counted as killed; exit 3 with the
usual breach lines), `file` skips the rest of a file that can't meet
`threshold.file`, `first` stops at the first survived mutant (exit 3,
`Error: stopped at the first surviving mutant, FILE:LINE (fail-fast first)`).
The results so far are saved; the next run tests only what was left. The
score line ends with `stopped early by fail-fast POLICY after N of M` or
`fail-fast file skipped N of M`. For a quick check after an edit,
`gooze run --fail-fast first --run '^Func$' ./pkg` answers fastest. v1.4.0+:
check `gooze run --help`.

| Exit | Meaning |
|---|---|
| 0 | done, every threshold met (or none set) |
| 1 | unexpected failure (I/O, reports, internal) |
| 2 | usage or config error |
| 3 | done, reports written, but a score is below a threshold (`Error: ... is below threshold.X N%` on stderr) or more mutants survive than `threshold.max_survivors` (`Error: N surviving mutants are above threshold.max_survivors M`) |
| 4 | git or diff error |
| 5 | OCI registry error (`report push` / `pull`) |
| 6 | no reports to view or merge |
| 7 | a package's tests fail without any mutation; its mutants weren't tested, the rest were scored |
| 130 | interrupted |

## Report files

`.gooze-reports/` holds one YAML file per mutation (named by a hash) plus
`_index.yaml` with totals. Cached results for a file are invalidated when its
source or test file changes, a mutagen version changes, or the file is deleted.
Reports record the mutation's `line`, and a `scope` when a run was narrowed;
a file holding partial results is re-tested in full by the next full run. `run/` holds the last narrowed run until `gooze report merge`.

## gooze.yaml keys

`output`, `no_cache`, `no_update_check`, `paths.exclude`, `run.parallel`,
`run.mutation_timeout`, `run.coverage_profile`, `run.diff`, `run.mutagens`,
`run.workspace`, `run.fail_fast`, `run.go_cache`, `run.go_cache_size`,
`run.go_cache_prewarm`, `mutagen.comparison.enum_bounds`, `threshold.total`,
`threshold.average`, `threshold.file`, `threshold.max_survivors`,
`threshold.diff.total`, `threshold.diff.average`, `threshold.diff.file`,
`report.format`, `log.filename`, `log.level`, `log.verbose`, `log.max_size`,
`log.max_backups`, `log.max_age` and `log.compress` (`--run` has no key, like
`go test -run`). Environment variables use the `GOOZE_` prefix (e.g.
`GOOZE_LOG_MAX_SIZE`, `GOOZE_RUN_MUTAGENS`). `gooze config show` (v1.5.0+)
lists every key with its effective value, source and env var; `gooze config
schema` prints the JSON Schema for editors.

- **v1.5.0+**: `no_cache` and `no_update_check` replace `no-cache` and
  `no-update-check`, which still work with a deprecation warning; older
  releases call the snake case names unknown. `version` is ignored, with a
  warning. `run.go_cache: isolated` (default; or `shared`) keeps the builds of
  mutants out of `GOCACHE` in gooze's own cache, trimmed to
  `run.go_cache_size` MB; `run.go_cache_prewarm` builds each package's tests
  in `GOCACHE` first.
- **v1.4.0+**: `mutagen.comparison.enum_bounds` (off) skips comparison
  mutants at an enum type's lowest and highest constant; only safe when no
  value of the type is converted from an arbitrary integer.
  `report.format` sets `gooze report view --format`.

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
