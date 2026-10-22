# Slow runs and timeouts

Read this when a gooze run is slower than expected, mutants end as `timeout`,
or gooze itself looks like the bottleneck. Measure before changing anything:
find out whether the time goes into generating mutants, into running the
tests, or into one mutant that never finishes.

## Generation or testing?

A run does two things: it generates mutants (parse, mutate, diff) and it runs
the tests once per mutant. `--estimate` does only the first, so timing it
separates the two:

```
time gooze run --estimate --no-cache ./...
```

`--no-cache` makes it look at every file, as a first run would. If the
estimate takes seconds and the run takes minutes, the time is in the tests;
skip to [Slow tests](#slow-tests). To see what an option costs, time the
estimate with and without it, e.g. `--mutagens branch`.

**One wall-clock number is not a measurement.** Other `gooze run` or
`go test` processes on the same machine share the CPU: the same estimate has
taken anywhere from 4 to 14 seconds depending on what else was running. Check
with `pgrep -fa "gooze run"` first, repeat a timing a few times, and prefer a
CPU profile (below), which shows where the time goes whatever the load.

## Slow tests

Every mutant reruns the package's whole test suite, so a 2-second suite times
300 mutants is 10 minutes on one worker. In order of payoff:

1. **Run in parallel**: `-p $(nproc)` (`run.parallel` in `gooze.yaml`). Above
   the core count it only adds contention.
2. **Make fewer mutants**: scope the run to a package, pass
   `--coverage-profile coverage.out` so uncovered lines are skipped, or use a
   narrowed run (`--run`, `--diff`, see [SKILL.md](SKILL.md)).
3. **Keep the overlay workspace** (the default). `deep-copy` tests in a copy of
   the project and is slower; use it only for the tests described in
   [killing-survivors.md](killing-survivors.md#tests-that-dont-see-the-mutant).
4. **Profile the suite itself**, since its cost is multiplied by the mutant
   count:

   ```
   go test -count=1 -cpuprofile cpu.out ./internal/foo/
   go tool pprof -top -cum -nodecount=30 cpu.out
   ```

   Slow setup (fixtures, sleeps, real network, big temp trees) shows up at the
   top. Suggest fixes to the user; don't rewrite their tests unasked.

## Timeouts

A mutant ends as `timeout` when its tests run past `--mutation-timeout`
(`run.mutation_timeout`, default 120 seconds). It is one of two things:

- **An infinite loop**: the mutant changed a loop condition so the loop never
  ends. Raising the timeout never helps.
- **A slow but finishing test**: raising the timeout helps, but the test is
  worth speeding up anyway.

A timeout counts as not killed in the score, so it fails a `threshold.*: 100`
gate even though the tests did notice the mutant.

**Tell them apart by applying the mutant by hand.** Take the original and
mutated line from `gooze report view` (or `gooze report view --all`), edit the
file in a scratch copy, and time the package tests against the unmutated
baseline:

```
timeout 300 go test -count=1 ./internal/foo/          # baseline, e.g. 2 s
# apply the mutated line, then:
timeout 300 go test -count=1 ./internal/foo/          # mutant
```

Exit status 124 means `timeout` killed it: the mutant never finished. Restore
the file afterwards.

An example of the infinite-loop case: a token scanner loop

```go
for {
	pos, tok, lit := s.Scan()
	if tok == token.EOF || file.Offset(pos) > offset {
		return found
	}
	// ...
}
```

has two mutants, `||` to `&&` and `==` to `<`, under which the package tests
went from 2 seconds to never finishing within 300. The fix is in the code or
the tests, not the timeout: bound the loop (for example by the input length,
since every token is at least one byte), or make it do less work per call so
the tests fail fast, and add a test for the edge case the condition guards.

## Profiling gooze itself

When generation is slow (the `--estimate` timing above), profile gooze. It
has no profiling flag, so build it from source with a throwaway hook. In a
clone of gooze (`git clone https://github.com/gooze-dev/gooze`), add a file to
package `main`, for example `zz_prof.go`:

```go
package main

import (
	"os"
	"runtime/pprof"

	"gooze.dev/pkg/gooze/cmd"
)

// Throwaway CPU profiling hook: never commit this file.
func init() {
	path := os.Getenv("GOOZE_CPUPROFILE")
	if path == "" {
		return
	}
	f, _ := os.Create(path)
	_ = pprof.StartCPUProfile(f)
	cmd.Execute()
	pprof.StopCPUProfile()
	f.Close()
	os.Exit(0)
}
```

Build it, remove the hook straight away, and profile a run in the project
being tested:

```
go build -o /tmp/gooze-prof . && rm zz_prof.go
cd /path/to/project
GOOZE_CPUPROFILE=/tmp/gooze.prof /tmp/gooze-prof run --estimate --no-cache ./...
go tool pprof -top -cum -nodecount=35 /tmp/gooze-prof /tmp/gooze.prof
```

Profile `gooze run` without `--estimate` the same way to include testing, but
most of that time is spent in the `go test` child processes, which this
profile doesn't see; profile the tests as in [Slow tests](#slow-tests).

**Reading `-top`.** `flat` is time spent in the function's own code, `cum` is
the time spent in it and everything it calls. Sorting by `cum` (`-cum`) puts
the call chain on top: `Estimate`, `StreamMutations` and the AST walk near
100% are expected. Look for the first function with a large `cum` that
shouldn't be there, then narrow down with a grep:

```
go tool pprof -top -cum -nodecount=200 /tmp/gooze-prof /tmp/gooze.prof | grep -E 'packageFiles|Parse|Diff'
```

A real reading, from an unreleased change, on gooze's own 70 files:

| Function | cum | What it meant |
|---|---|---|
| `UnifiedDiffer.Diff` | ~27% | the diff of each mutant, the expected main cost |
| `runtime.gcBgMarkWorker` | ~27% | garbage collection: allocation per mutant |
| `packageFiles` → `parser.ParseFile` | 18% | the change re-parsed every file of a package for each source file: a bug, fixed by parsing once per package |

To compare two builds (before and after a change, or a release and a
branch), build both, and profile or time the same command with each. Report a
gooze performance problem as an issue on
[gooze-dev/gooze](https://github.com/gooze-dev/gooze/issues) with the
command, the file and mutant counts from `--estimate`, and the top of the
profile.

## Tooling gotcha: golangci-lint on Go 1.27

gooze's module needs Go 1.27. A `golangci-lint` built with an older Go fails
with `the Go language version (go1.26) used to build golangci-lint is lower
than the targeted Go version`. Run `go install` for it from inside the
module, so the `go.mod` toolchain line picks the right Go (gooze's own
`make install-golangci-lint` does this); running it elsewhere builds it with
the default Go again.
