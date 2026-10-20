---
name: mutation-testing
description: Run gooze mutation testing on Go code and kill surviving mutants by writing better tests. Use when the user asks about mutation testing, gooze, a mutation score, surviving or not-covered mutants, test quality or test gaps in a Go project, //gooze:ignore directives, or gooze.yaml.
allowed-tools: Bash(gooze run *) Bash(gooze report view) Bash(gooze version) Bash(goozels check *)
---

# Mutation testing with gooze

gooze mutates Go source (flips `<` to `<=`, `+` to `-`, `true` to `false`, deletes
statements, …) and runs the tests against each mutant. A **killed** mutant made a
test fail: good. A **surviving** mutant means the tests still pass with that bug,
so a test is missing or too weak. **Not covered** means no test even runs that line.

## The loop

1. **Check the tools.** `gooze version`. If it's missing:
   `go install gooze.dev/pkg/gooze@latest`. For diagnostics after each edit, the
   `goozels` binary is optional: `go install gooze.dev/pkg/goozels/cmd/goozels@latest`.
2. **Scope the run** to the package being worked on, not `./...`, unless asked:
   `gooze run --estimate ./internal/foo/...` previews files and mutation counts.
3. **Run:** `gooze run ./internal/foo/...`. Reports go to `.gooze-reports/`.
   Runs are incremental: unchanged files are skipped. Use `-p N` to parallelize.
4. **Read the results.** `goozels check <file.go>` prints the file's score and one
   line per surviving mutant with the exact change, e.g.
   `calc.go:12:2: warning: gooze: surviving comparison mutant — tests still pass with: if n >= 0 {`.
   Checking a `_test.go` file also lists the survivors of the source files it
   tests. With the goozels hook installed, these lines appear by themselves after
   each edit, including test edits. Without goozels, use `gooze report view`.
5. **Kill survivors by improving tests**, not by changing production code. For
   each survivor, write a test whose assertion fails under that exact mutation:
   - `<` vs `<=`: test the boundary value itself.
   - `+` vs `-`, numeric literal `5` → `0`/`1`: assert the exact computed value.
   - deleted statement: assert the side effect it has (state, return, call).
   - `&&` vs `||`, negated condition: cover the case where the operands differ.
   Not-covered mutants need a test that executes the line at all.
6. **Rerun gooze** on the same package and confirm the score went up. A new
   test doesn't change the score until gooze runs again.

## When a mutant can't be killed

Some mutants are *equivalent*: the change doesn't alter behaviour (e.g. `i < len`
vs `i != len` in a loop that only ever increments by one). Don't write a test
that can't exist. Explain why it is equivalent, then suppress it narrowly:

```go
for i := 0; i < n; i++ { //gooze:ignore comparison
```

`//gooze:ignore` with names (comma or space separated) skips those mutagens;
with no names it skips all of them. Prefer naming the mutagen. Ask before adding
ignores in bulk.

## gooze.yaml

gooze reads only `./gooze.yaml`. If it can't parse it, gooze **ignores the whole
file** and runs on defaults, with only a one-line warning. `goozels check
gooze.yaml` validates it. A common slip is `key:value` without a space after
the colon.

## Reference

Mutagens, flags, statuses, report files and CI: see [reference.md](reference.md).
