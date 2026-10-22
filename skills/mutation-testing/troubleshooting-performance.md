# Slow runs and timeouts

Read this when a gooze run is slower than expected, mutants end as `timeout`
(often an infinite loop), a run is slow or fails only in CI, or gooze itself
looks like the bottleneck. Measure before changing anything:
find out whether the time goes into generating mutants, into running the
tests, or into one mutant that never finishes.

## Suggest only fixes you have tried

The user acts on what you suggest, so a fix that doesn't work costs them a
run, or a CI cycle, for nothing. For every problem:

1. **Measure the baseline**: the timing, the profile, or the mutant's status.
2. **Try the fix without touching the user's files**, through
   `go test -overlay` (see [Trying a change](#trying-a-change-without-editing-files)),
   or in a scratch copy of the project.
3. **Measure again with the same command.** Keep the fix only if the number
   moved: the tests got faster, the mutant is now `killed`, the timeout is
   gone.
4. **Then suggest it**, with the before and after numbers and the exact edit.
   Change the user's code only if they agree.

Don't suggest what can't work. Raising `--mutation-timeout` never fixes an
infinite loop. `-p` above the core count doesn't speed anything up. A
`//gooze:ignore` is not a fix for a mutant the tests can detect. If nothing
you tried helped, say so, show what you measured, and leave the code as it
is.

## Trying a change without editing files

`go test -overlay` swaps files in for one test run, the way gooze tests its
mutants, so you can try a mutant or a fix and leave the project untouched.
Write the changed file to a temporary directory, then a JSON file that maps
the original's absolute path to it:

```
mkdir -p /tmp/try
cp internal/foo/scan.go /tmp/try/scan.go          # then edit /tmp/try/scan.go
printf '{"Replace":{"%s":"/tmp/try/scan.go"}}\n' "$PWD/internal/foo/scan.go" > /tmp/try/overlay.json
go test -count=1 -overlay /tmp/try/overlay.json ./internal/foo/
```

Several files go in the same `Replace` map; a test file can be replaced too,
to try a new or faster test. The overlay is invisible to code the test builds
or reads in another process (see
[killing-survivors.md](killing-survivors.md#tests-that-dont-see-the-mutant));
for those tests, try the change in a scratch copy of the project instead.

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
estimate with and without it, e.g. `--mutagens branch`. If generation itself
is slow, see [Profiling gooze itself](#profiling-gooze-itself).

**One wall-clock number is not a measurement.** Other `gooze run` or
`go test` processes on the same machine share the CPU: the same estimate has
taken anywhere from 4 to 14 seconds depending on what else was running. Check
with `pgrep -fa "gooze run"` first, repeat a timing a few times, and prefer a
CPU profile, which shows where the time goes whatever the load.

## Slow tests

Every mutant reruns the package's whole test suite, so a 2-second suite times
300 mutants is 10 minutes on one worker. Work through these in order; each
says how to check it helped before you suggest it.

1. **Run in parallel**: `-p $(nproc)` (`run.parallel` in `gooze.yaml`).
   Check: the same `gooze run` with a few hundred mutants finishes in roughly
   1/N of the time. Above the core count it only adds contention, and tests
   that share files or ports between workers may start failing; if they do,
   that's a test isolation problem to report, not a reason to suggest a lower
   `-p` silently.
2. **Make fewer mutants**: scope the run to the package being worked on, pass
   `--coverage-profile coverage.out` so uncovered lines are skipped, or use a
   narrowed run (`--run`, `--diff`, see [SKILL.md](SKILL.md)). Check: the
   mutant count from `gooze run --estimate` with the same flags drops.
3. **Keep the overlay workspace** (the default). `deep-copy` tests in a copy of
   the project and is slower; it's needed only for the tests described in
   [killing-survivors.md](killing-survivors.md#tests-that-dont-see-the-mutant).
   If `gooze.yaml` sets `run.workspace: deep-copy`, check whether it's still
   needed: run the same selection with `--workspace overlay` and compare the
   statuses. Suggest switching back only if every mutant ends the same way.
4. **Speed up the suite itself**, since its cost is multiplied by the mutant
   count. Profile it:

   ```
   go test -count=1 -cpuprofile cpu.out ./internal/foo/
   go tool pprof -top -cum -nodecount=30 cpu.out
   go test -count=1 -v ./internal/foo/ 2>&1 | grep -E -- '--- (PASS|FAIL)' | sort -t'(' -k2 -n | tail
   ```

   The `-v` line lists the slowest tests last. Common causes, each a concrete
   fix to try through the overlay and time before suggesting:
   - `time.Sleep` or polling with a fixed wait: wait on a channel or a
     condition, or inject a clock.
   - Real network or databases: a fake or an `httptest.Server`.
   - Large fixtures built in every test: build once in `TestMain` or with
     `sync.Once`, or shrink them.
   - Independent tests run one by one: `t.Parallel()`, if they share no state.
   - Retries and backoff with real delays: make the delay a parameter the
     test sets to zero.

   Report the before and after time of the suite and of one `gooze run`, not
   just "should be faster".

## Timeouts

A mutant ends as `timeout` when its tests run past `--mutation-timeout`
(`run.mutation_timeout`, default 120 seconds). It is one of two things:

- **An infinite loop**: the mutant changed a loop condition so the loop never
  ends. Raising the timeout never helps; don't suggest it.
- **A slow but finishing test**: raising the timeout helps, but the test is
  worth speeding up anyway (see [Slow tests](#slow-tests)).

A timeout counts as not killed in the score, so it fails a `threshold.*: 100`
gate even though the tests did notice the mutant.

**Tell them apart by applying the mutant through an overlay.** Take the
original and mutated line from `gooze report view` (or `gooze report view
--all`), put the mutated file in `/tmp/try` as in
[Trying a change](#trying-a-change-without-editing-files), and time the
package tests against the unmutated baseline:

```
time timeout 300 go test -count=1 ./internal/foo/                                    # baseline, e.g. 2 s
time timeout 300 go test -count=1 -overlay /tmp/try/overlay.json ./internal/foo/     # the mutant
```

Exit status 124 means `timeout` stopped it: the mutant never finished, so it
is an infinite loop. If it finishes, compare its time with the mutation
timeout and the baseline to see how slow it is.

### Fighting infinite-loop mutants

A mutant that makes a loop spin is a sign the function does too much: the
loop is buried in it, so no test reaches the edge case where the mutated
condition never becomes false. Fix the code's shape, in this order, trying
each through the overlay before suggesting it:

1. **Move the loop into its own small function and test it directly**, with
   table cases for the edge that made it spin: empty input, the last
   position, a value at the end of the input.
2. **Bound the loop** so a mutated condition can't spin, and make the bound
   itself killable: add a case that needs exactly that many iterations.
   Otherwise the bound's own `+ 1` or `<` mutants survive as equivalents.
3. **Replace counter loops over ranges with data.** A loop that fills one
   map entry per line, `for line := first; line <= last; line++`, has a
   `line >= last` mutant that never ends when `first == last`. Store the
   `[first, last]` range instead and look a line up with a small function.

A real case, a token scanner:

```go
for {
	pos, tok, lit := s.Scan()
	if tok == token.EOF || file.Offset(pos) > offset {
		return found
	}
	// ...
}
```

Its `tok < token.EOF` and `||` to `&&` mutants loop forever only when
`offset` equals the input length, a deletion at the end of the file: EOF's
offset is then not greater than `offset`, and the mutated test for EOF never
fires. The package tests went from 2 seconds to never finishing. The fix:

- extract `tokenAt(src, offset)` and `tokenText(tok, lit)` and test both
  directly, including `offset == len(src)` and an empty `src`;
- bound the scan with `for range len(src) + 1`, since every token but one is
  at least one byte;
- pin the bound with a case that needs every iteration: `src` `a<b` at offset
  3 needs 4 tokens, because the scanner inserts a zero-width `;` at the end,
  so a bound of `len(src)` returns `b` and `len(src) - 1` returns `<`, and
  both get killed.

**Check each fix the same way you diagnosed it.** With the fix applied (in a
scratch copy or the overlay), apply the mutant again and run the tests under
`timeout 60`: exit status 124 means it still hangs, and a fixed loop makes
the tests **fail** within seconds. Then confirm with gooze itself. gooze
builds its own overlay from the files on disk, so copy the project to a
scratch directory, apply the fix there, run
`gooze run --run '^Func$' ./internal/foo` in the copy, and check the mutant
now ends as `killed`, not `timeout`. Suggest the fix with that result. Never
raise `run.mutation_timeout` to make an infinite loop pass.

## Slow, timing out or failing only in the pipeline

When mutants time out or survive in CI but not locally, reproduce the CI run
instead of guessing. The usual causes:

- **Fewer, slower cores.** A GitHub `ubuntu-latest` runner has 4 vCPUs and
  16 GB. `-p` above the runner's cores, or several gooze jobs sharing one
  machine, makes tests slow enough to time out: those timeouts aren't real.
  Keep `-p` at or below the runner's cores, and with shards, `-p` times the
  shards per machine.
- **Running as root.** In a `golang` container the job runs as root, so tests
  that rely on file permissions skip themselves, and the mutants they would
  kill survive only in CI. Run the job on the runner with
  `actions/setup-go` instead of in the container.
- **The diff run covers more than the change.** See
  [SKILL.md](SKILL.md#narrowed-runs-one-function-some-mutagens-a-branchs-changes):
  editing a test file pulls its whole source file into `--diff`.

**Reproduce under runner-like limits**, in a fresh clone, not the working
copy, so local reports and edits don't leak in. Pin the cores with `taskset`
(Go sizes `GOMAXPROCS` from the CPU affinity) and cap memory with a systemd
scope, then run exactly the workflow's commands, for example for a PR with
sharded diff runs:

```
git clone https://github.com/OWNER/REPO /tmp/ci-repro && cd /tmp/ci-repro && git checkout BRANCH
for i in 0 1 2 3 4 5; do
  taskset -c 0-3 systemd-run --user --scope -p MemoryMax=16G gooze run -p 2 -s $i/6 --diff origin/main ./...
done
gooze report merge -o .gooze-reports/run
gooze report view -o .gooze-reports/run --threshold-total 100
```

`taskset` limits the number of cores, not their speed, so a laptop core is
still faster than a runner's. A CPU quota needs the cgroup cpu controller,
which often isn't delegated to users, and Docker runs as root, which brings
back the permission skips above. Treat a local pass as necessary, not as
proof; a timeout that appears only under these limits is a slow test (see
[Slow tests](#slow-tests)), and one that appears without them too is an
infinite loop.

**Shape the pipeline so pull requests stay fast**: run the shards themselves
with `--diff` on pull requests (each shard tests its share of the changed
lines) rather than a separate unsharded diff job next to full shards, and
keep the full sharded run, with the baseline publish, on the default branch.
See the ci-setup skill for the workflow.

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

To check a fix to gooze, build both versions, then profile or time the same
command with each, several times. Report a gooze performance problem as an
issue on [gooze-dev/gooze](https://github.com/gooze-dev/gooze/issues) with the
command, the file and mutant counts from `--estimate`, the top of the
profile, and the fix if you measured one; don't present an untested idea as
the fix.

## Tooling gotcha: golangci-lint on Go 1.27

gooze's module needs Go 1.27. A `golangci-lint` built with an older Go fails
with `the Go language version (go1.26) used to build golangci-lint is lower
than the targeted Go version`. Run `go install` for it from inside the
module, so the `go.mod` toolchain line picks the right Go (gooze's own
`make install-golangci-lint` does this); running it elsewhere builds it with
the default Go again.
