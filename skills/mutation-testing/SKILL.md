---
name: mutation-testing
description: Runs gooze mutation testing on Go code and kills surviving mutants by writing better tests, following the project's own testing conventions. Use when the user asks about mutation testing, gooze, a mutation score, surviving or not-covered mutants, test quality or test gaps in a Go project, //gooze:ignore directives, or gooze.yaml.
allowed-tools: Bash(gooze run *) Bash(gooze report view) Bash(gooze report view *) Bash(gooze report merge) Bash(gooze version) Bash(goozels check *) Bash(go test *) Bash(go tool cover *) Bash(gocyclo *)
---

# Mutation testing with gooze

gooze mutates Go source (flips `<` to `<=`, `+` to `-`, `true` to `false`, deletes
statements, …) and runs the tests against each mutant. A **killed** mutant made a
test fail: good. A **surviving** mutant means the tests still pass with that bug,
so a test is missing or too weak. **Not covered** means no test even runs that line.

**Setting the project up rather than testing code?** For a request to "set up
mutation testing", don't run gooze or edit files yet. Suggest `/gooze:init`
(gooze.yaml, the CLAUDE.md/AGENTS.md guide, permission rules), and for an
existing Makefile or CI file use the `ci-setup` skill (`/gooze:ci-setup`).
Change nothing until the user agrees.

## Before mutating: coverage and complexity

Mutation testing pays off on code with high coverage and low cyclomatic
complexity. Check both before a run and tell the user what you find.

- **Coverage (aim for ~80%+).** `go test -coverprofile=coverage.out ./internal/foo/...`,
  then `go tool cover -func=coverage.out`. Uncovered lines only yield
  not-covered mutants, so write tests for them first: it is cheaper than a
  mutation run. Then pass the profile so gooze skips lines still uncovered:
  `gooze run --coverage-profile coverage.out ./internal/foo/...`.
- **Complexity (aim for ≤10 per function).** If `gocyclo` is installed,
  `gocyclo -over 10 ./internal/foo` lists the offenders (install:
  `go install github.com/fzipp/gocyclo/cmd/gocyclo@latest`, ask first). Complex
  functions spawn many mutants that need many tests; suggest splitting them
  before chasing their survivors, but don't refactor production code unasked.

## The loop

1. **Check the tools.** `gooze version`. If it's missing:
   `go install gooze.dev/pkg/gooze@latest`. For diagnostics after each edit, the
   `goozels` binary is optional: `go install gooze.dev/pkg/goozels/cmd/goozels@latest`.
   **Keep them up to date.** gooze and goozels print a line like
   `gooze v1.3.0 is available (you have v1.2.0). Update: go install …@latest`
   on stderr, and the session check reports the same at startup. When you see
   one, tell the user and offer that command, but run it only if they agree:
   it changes their installed tools. After a gooze update, offer `/gooze:init`
   to refresh the guide, and point out any pinned versions in CI or Makefiles
   (`gooze@vX.Y.Z`, `GOOZE_VERSION`); those are bumped deliberately, never
   silently. After an upgrade, the next run re-tests files whose mutagens
   changed, so scores can move. The notice never blocks or fails a run, so
   keep going either way.
2. **Scope the run** to the package being worked on, not `./...`, unless asked:
   `gooze run --estimate ./internal/foo/...` previews files and mutation counts.
3. **Run in parallel:** `gooze run -p $(nproc) --coverage-profile coverage.out ./internal/foo/...`.
   Each mutant compiles and tests the package, so a serial run of a few hundred
   mutants takes many minutes; `-p` with one worker per core cuts that roughly
   by the core count. Reports go to `.gooze-reports/`. Runs are incremental:
   unchanged files are skipped and their earlier results still count in the
   score. `--no-cache` re-tests everything (there is no `--force`).
   Working on one function, a few mutagens, or a branch's changes? Use a
   narrowed run (next section) for a faster loop.
4. **Read the results.** `goozels check <file.go>` prints the file's score, then
   one line per line of code with surviving mutants, showing original → mutated:
   - `calc.go:1:1: warning: gooze: score 87.50% — 14 killed, 2 survived`
   - ``calc.go:10:2: warning: gooze: surviving comparison mutant — tests still pass with `if n < lo {` → `if n <= lo {` ``
   - ``ignore.go:108:3: warning: gooze: 6 surviving mutants (comparison ×5, numbers) — tests still pass with `…` → `… != 0 {`, …``

   Checking a `_test.go` file also lists the survivors of the source files it
   tests. With the goozels hook installed, these lines appear by themselves after
   each edit (`gooze results from the last run:`), including test edits. Without
   goozels, use `gooze report view [paths]`.
   - **`results are from before X changed`**: the file changed since gooze ran,
     so no line markers are shown. Rerun the command it prints before trusting
     any score.
   - **`tests changed since the last run`**: the score predates your new
     tests; rerun to see their effect.
   - **`no gooze results for X yet`**: gooze hasn't run on it (or found nothing
     to mutate); run the command it prints.
5. **Kill survivors by improving tests**, not by changing production code.
   First read how this project tests (a testing section in `CLAUDE.md` or
   `AGENTS.md`, `TESTING*.md`, the neighbouring `_test.go` files) and write
   the new test the same way. For each survivor, decide first: **gap or
   equivalent?** Can any input make the mutated line behave differently? If
   yes, write the test that observes it:
   - `<` vs `<=`: test the boundary itself, and both sides (`N-1`, `N`, `N+1`).
   - `+` vs `-`, a literal `5` → `0`/`1`: assert the exact value.
   - `&&` vs `||`, `!`: a case where exactly one operand is true.
   - `NoError` alone or `NotNil` on a slice lets mutants survive: assert the
     value and the length.
   Not-covered mutants need a test that executes the line at all. The full
   method, with the case checklist and assertion pitfalls, is in
   [killing-survivors.md](killing-survivors.md). Label every survivor (gap
   fixed, or equivalent with a reason); don't chase a 100% score.
6. **Rerun gooze** on the same package (same flags, without `--no-cache`) and
   confirm the survivor is gone and the score went up. A new test doesn't
   change the score until gooze runs again.

## Narrowed runs: one function, some mutagens, a branch's changes

Older gooze releases don't have these flags: check that `gooze run --help`
lists `--run` (and `--diff`, `--mutagens`) before using them. If it doesn't,
say so and offer the update (`go install gooze.dev/pkg/gooze@latest`); don't
guess flags.

- **One function**, like `go test -run` but on the code being mutated:
  `gooze run -p $(nproc) --run '^InRange$' ./internal/foo`. The pattern is a
  regex matched against `Name`, and `Type.Name` for methods. It's unanchored,
  so write `^Name$` for one function. Closures count as part of their
  function. Preview with `gooze run --estimate --run '^InRange$' ./internal/foo`.
- **Some mutagens**: `--mutagens comparison` (comma-separated: arithmetic,
  boolean, numbers, comparison, logical, unary), e.g. while killing
  comparison survivors.
- **A branch's changes**: `gooze run --diff origin/main ./...` mutates only
  lines changed since the merge base, plus whole files whose tests changed.
  Needs git and the base ref fetched.

How they behave:
- A narrowed run writes to `.gooze-reports/run/` (replaced each time) and
  never changes the main reports. Read it with
  `gooze report view -o .gooze-reports/run`. `goozels check` and the edit hook
  show the main reports only, so they don't see a narrowed run until it is
  merged.
- Its score covers only the selection, which the score line names, e.g.
  `(...; 0 cached, 4 tested; functions matching ^InRange$)`.
- It uses the cache: a file unchanged since the last run is skipped. Editing
  its test file makes it re-test; `--no-cache` forces it.
- When the function is done, run `gooze report merge`. For an unchanged file
  it replaces just those mutants and the file stays complete. For a changed
  file it replaces the file's results and marks them partial, so the next
  full `gooze run` re-tests the whole file.

Don't:
- Report a narrowed score as the package's or project's score. Merge, then
  `gooze report view` (or run the package) for that.
- Use `--mutagens` to hide survivors you'd rather not fix. Only equivalent
  mutants get a `//gooze:ignore`, with a reason.
- Expect `--run` to make each mutant faster: the package's whole test suite
  still runs per mutant. It only cuts the number of mutants.
- Combine `--run` with `--shard` (gooze rejects it), or use `--run` or
  `--mutagens` in CI.
- Push a narrowed run as a registry baseline (`gooze report push`). Baselines
  come from full runs on the default branch.

## When a mutant can't be killed

Some mutants are *equivalent*: the change doesn't alter behaviour (e.g. `i < len`
vs `i != len` in a loop that only ever increments by one). Don't write a test
that can't exist. Explain why it is equivalent, then suppress it narrowly:

```go
for i := 0; i < n; i++ { //gooze:ignore comparison
```

`//gooze:ignore` with names (comma or space separated) skips those mutagens;
with no names it skips all of them. A directive covers **every** mutant of that
mutagen on its line, including killable ones, so first kill those with tests,
and put the reason in a comment on the line above. Ignore only mutants that
cannot change behaviour, never code that is merely hard to test (`main`,
stdin, real network): leave those as honest survivors. gooze v1.2.0+ no longer
generates the common equivalents of comparing a string with `""` or a
`len`/`cap` with `0`, so don't add ignores for those. Ask before adding ignores
in bulk.

## gooze.yaml

gooze reads only `./gooze.yaml`. If it can't parse it, gooze **ignores the whole
file** and runs on defaults, with only a one-line warning. `goozels check
gooze.yaml` validates it. A common slip is `key:value` without a space after
the colon.

## Reference

- Writing the test that kills a survivor: [killing-survivors.md](killing-survivors.md).
- Mutagens, flags, statuses, report files and CI: [reference.md](reference.md).
