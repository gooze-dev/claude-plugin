---
name: mutation-testing
description: Run gooze mutation testing on Go code and kill surviving mutants by writing better tests. Use when the user asks about mutation testing, gooze, a mutation score, surviving or not-covered mutants, test quality or test gaps in a Go project, //gooze:ignore directives, or gooze.yaml.
allowed-tools: Bash(gooze run *) Bash(gooze report view) Bash(gooze version) Bash(goozels check *) Bash(go test *) Bash(go tool cover *) Bash(gocyclo *)
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
2. **Scope the run** to the package being worked on, not `./...`, unless asked:
   `gooze run --estimate ./internal/foo/...` previews files and mutation counts.
3. **Run in parallel:** `gooze run -p $(nproc) --coverage-profile coverage.out ./internal/foo/...`.
   Each mutant compiles and tests the package, so a serial run of a few hundred
   mutants takes many minutes; `-p` with one worker per core cuts that roughly
   by the core count. Reports go to `.gooze-reports/`. Runs are incremental:
   unchanged files are skipped and their earlier results still count in the
   score. `--no-cache` re-tests everything (there is no `--force`).
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
5. **Kill survivors by improving tests**, not by changing production code. For
   each survivor, write a test whose assertion fails under that exact mutation:
   - `<` vs `<=`: test the boundary value itself.
   - `+` vs `-`, numeric literal `5` → `0`/`1`: assert the exact computed value.
   - deleted statement: assert the side effect it has (state, return, call).
   - `&&` vs `||`, negated condition: cover the case where the operands differ.
   Not-covered mutants need a test that executes the line at all.
6. **Rerun gooze** on the same package (same flags, without `--no-cache`) and
   confirm the score went up. A new test doesn't change the score until gooze
   runs again.

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

Mutagens, flags, statuses, report files and CI: see [reference.md](reference.md).
