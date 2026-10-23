# GitHub Actions

## Contents

- Triggers
- 1. Single job with the incremental cache (recommended start)
- 2. Sharded (large repos)
- 3. Baseline in GHCR instead of actions/cache (optional)
- Thresholds (optional)
- Survivors on the pull request and in code scanning (optional)

Add a `mutation` job to an **existing** workflow (usually the one that runs
`go test`). Don't create a new workflow file. Copy from that workflow: list
style and indentation, `runs-on`, `actions/checkout` / `actions/setup-go`
versions and their `with:` (`go-version`, `go-version-file`, `cache`), or the
`container: golang:X` image if it uses one instead of setup-go (then drop the
setup-go step; `/go/bin` is already on `PATH`). setup-go puts `$(go env GOPATH)/bin`
on `PATH`, so `gooze` is callable after `go install`. A container job runs as
root, where tests that rely on file permissions skip themselves and their
mutants survive only in CI; if the project has such tests, suggest the
mutation job runs on the runner with setup-go even when other jobs use a
container.

## Triggers

Mutation testing should run on pull requests, plus the default branch so it
refreshes the cache that PRs restore. If the workflow also runs on pushes to
every branch, guard the job:

```yaml
    if: github.event_name == 'pull_request' || github.ref == format('refs/heads/{0}', github.event.repository.default_branch)
```

Optional nightly full re-test: add `schedule: [{cron: "0 3 * * *"}]` to `on:`
(warn that this also runs the workflow's other jobs nightly) and pass
`--no-cache` only then (see the run step below).

## 1. Single job with the incremental cache (recommended start)

Restore `.gooze-reports/` from the most recent run (a PR can restore caches
saved on its base branch), run, save under the commit SHA.

```yaml
  mutation:
    runs-on: ubuntu-latest
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version-file: go.mod        # same as the existing test job
      - name: Install gooze
        run: GOTOOLCHAIN=auto go install gooze.dev/pkg/gooze@v1.3.0
      - name: Restore gooze reports
        uses: actions/cache/restore@v4
        with:
          path: .gooze-reports
          key: gooze-reports-${{ github.sha }}
          restore-keys: gooze-reports-
      - name: Mutation testing
        run: gooze run -p 4 ${{ github.event_name == 'schedule' && '--no-cache' || '' }} ./...
      - name: Save gooze reports
        if: ${{ !cancelled() }}         # also when a threshold fails (exit 3)
        uses: actions/cache/save@v4
        with:
          path: .gooze-reports
          key: gooze-reports-${{ github.sha }}
      - name: Mutation score
        run: gooze report view
```

Notes:
- Drop the `schedule` expression if no schedule trigger is added:
  `run: gooze run -p 4 ./...`.
- Scope paths / add `-x` excludes the same way the test job does. If the
  repo has a `mutation` Make target, use `run: make install-gooze mutation`.
- Save is a separate step with `if: ${{ !cancelled() }}`, so the cache is
  kept even when a threshold fails the run or view step.
- If gooze's install line already uses Go >= 1.27.3, `GOTOOLCHAIN=auto` can be
  dropped.

## 2. Sharded (large repos)

Matrix of shards; each runs `-s INDEX/TOTAL` (0-based) and writes
`.gooze-reports/shard_INDEX/`. A merge job collects them and runs
`gooze report merge`. Shard dirs are tarred so artifact upload/download keeps
the `shard_N/` layout exactly (this is what gooze's own CI does).

```yaml
  mutation:
    runs-on: ubuntu-latest
    timeout-minutes: 60
    strategy:
      fail-fast: false
      matrix:
        shard: [0, 1, 2, 3]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version-file: go.mod
      - name: Install gooze
        run: GOTOOLCHAIN=auto go install gooze.dev/pkg/gooze@v1.3.0
      - name: Restore gooze reports
        uses: actions/cache/restore@v4
        with:
          path: .gooze-reports
          key: gooze-reports-${{ github.sha }}
          restore-keys: gooze-reports-
      - name: Run shard ${{ matrix.shard }}
        run: gooze run -p 2 -s ${{ matrix.shard }}/4 ./...
      - name: Archive shard reports
        run: tar -czf "shard_${{ matrix.shard }}.tgz" -C .gooze-reports "shard_${{ matrix.shard }}"
      - uses: actions/upload-artifact@v4
        with:
          name: shard_${{ matrix.shard }}
          path: shard_${{ matrix.shard }}.tgz
          if-no-files-found: error

  mutation-merge:
    needs: mutation
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version-file: go.mod
      - name: Install gooze
        run: GOTOOLCHAIN=auto go install gooze.dev/pkg/gooze@v1.3.0
      # Base reports first, so files no shard re-tested keep their cached results.
      - name: Restore gooze reports
        uses: actions/cache/restore@v4
        with:
          path: .gooze-reports
          key: gooze-reports-${{ github.sha }}
          restore-keys: gooze-reports-
      - uses: actions/download-artifact@v4
        with:
          path: shard-archives
          pattern: shard_*
          merge-multiple: true
      - name: Merge shards
        run: |
          mkdir -p .gooze-reports
          for archive in shard-archives/*.tgz; do tar -xzf "$archive" -C .gooze-reports; done
          gooze report merge
      - name: Save gooze reports
        if: ${{ !cancelled() }}         # also when a threshold fails (exit 3)
        uses: actions/cache/save@v4
        with:
          path: .gooze-reports
          key: gooze-reports-${{ github.sha }}
      - name: Mutation score
        run: gooze report view
```

Keep the shard count in the matrix and in `-s N/4` in sync. Gate only in the
merge job: shards don't check thresholds, and one shard's score covers only
its slice.

## 3. Baseline in GHCR instead of actions/cache (optional)

For a baseline shared with teammates (`gooze report pull` locally too), or
beyond actions/cache's 7-day eviction. Replace the cache restore/save steps:

```yaml
    permissions:
      contents: read
      packages: write          # read is enough for jobs that only pull
    env:
      REPORTS_REF: ghcr.io/${{ github.repository }}/gooze-reports:main
      GOOZE_REGISTRY_USERNAME: ${{ github.actor }}
      GOOZE_REGISTRY_PASSWORD: ${{ secrets.GITHUB_TOKEN }}
    steps:
      # ...
      - name: Restore baseline from main
        run: gooze report pull "$REPORTS_REF" || echo "no baseline yet"
      # ... gooze run (and merge) ...
      - name: Publish baseline (default branch only)
        if: github.ref == format('refs/heads/{0}', github.event.repository.default_branch)
        run: gooze report push "$REPORTS_REF"
```

- `ghcr.io` references must be lowercase; if the owner/repo has capitals,
  write the path literally in lowercase.
- Job-level `permissions:` replaces the workflow-level set, so list
  `contents: read` too. If the workflow has a top-level `permissions:` block,
  extend it there instead.
- Only the default branch (and with shards, only the merge job) pushes; PRs
  only pull. Fork PRs get a read-only token, which is fine for pulling a
  public package; a failed pull just means a full run (`|| echo`).

## Thresholds (optional)

Flags, exit codes and the `gooze run --help` check:
[SKILL.md](SKILL.md#thresholds-and-exit-codes). Gate on the last step (after
the cache save), in the merge job when sharded:

```yaml
      - name: Mutation score
        run: gooze report view --threshold-total 60
```

Exit 3 fails the job. If the threshold is in `gooze.yaml` instead, the run
(or merge) step fails first; the `if: ${{ !cancelled() }}` on the save step
keeps the cache. To report without failing, wrap it:
`run: gooze report view --threshold-total 60 || [ $? -eq 3 ]`.

Pull requests, scored on the changed lines only (checkout needs
`fetch-depth: 0` for the merge base):

```yaml
      - name: Mutation testing (changed lines)
        if: github.event_name == 'pull_request'
        run: gooze run -p 4 --diff "origin/${{ github.base_ref }}" --threshold-diff-total 80 ./...
```

Give the full run step `if: github.event_name != 'pull_request'`. A `--diff`
run writes only `.gooze-reports/run/`, so the default branch's full run keeps
the cache current.

When the repo is sharded, shard the pull request's diff run too, instead of
adding one unsharded diff job: give each shard's run step `--diff` on pull
requests (`gooze run -p 2 -s INDEX/TOTAL --diff "origin/${{ github.base_ref }}" ./...`),
which writes `.gooze-reports/run/shard_INDEX/`. Archive from
`.gooze-reports/run`, extract there in the merge job, skip the baseline pull
on pull requests, and gate on the merged changed lines:

```yaml
      - name: Merge shards
        run: gooze report merge -o .gooze-reports/run
      - name: Changed lines must be killed
        if: github.event_name == 'pull_request'
        run: gooze report view -o .gooze-reports/run --threshold-total 100
```

Pass the threshold as a flag there: gooze v1.3.0 doesn't apply
`threshold.diff.*` from `gooze.yaml` to merged diff shards. Push and pull
requests then share one matrix: full shards and the baseline publish on the
default branch, diff shards on pull requests. A shard with no changed lines
still writes its directory, so the merge and gate pass with
`100.00% (no mutations)`.

## Survivors on the pull request and in code scanning (optional)

A failed gate says the score dropped, not where. `gooze report view --format github`
prints a workflow annotation per line with surviving mutants (then the usual
summary), and GitHub shows it on that line of the PR's changed files.
`--format sarif` writes a SARIF 2.1.0 log instead of the summary, for GitHub
code scanning. Use them only if the pinned gooze's `gooze report view --help`
lists `--format` (newer than v1.3.0); otherwise offer a version bump or skip it.
Docs: <https://gooze.dev/docs/ci/github#survivors>.

Annotations, in the pull request job. Take the threshold off the run step,
so the view step always runs, and gate there instead:

```yaml
      - name: Mutation testing (changed lines)
        if: github.event_name == 'pull_request'
        run: gooze run -p 4 --diff "origin/${{ github.base_ref }}" ./...
      - name: Annotate survivors
        if: github.event_name == 'pull_request'
        run: gooze report view -o .gooze-reports/run --format github --threshold-diff-total 80
```

When the diff run is sharded, put `--format github` on the merged gate
instead: `gooze report view -o .gooze-reports/run --format github --threshold-total 100`.

- A line with a surviving mutant is a `warning`; a line whose mutants are only
  not covered, timed out or skipped is a `notice`. Several mutants on one line
  make one annotation, so GitHub's per-step annotation limit counts lines.
- Paths are relative to the git repository root, so a module in a
  subdirectory works when the step runs there (`working-directory:`).
- Prefer the flag or `GOOZE_REPORT_FORMAT: github` in the job's `env:`. Don't
  put `report.format: github` in `gooze.yaml`: local `gooze report view` would
  print annotations too.
- `--all` can't be combined with `--format github|sarif` (exit 2).

Code scanning, from the default branch's full run (the merge job when
sharded), so alerts track survivors across commits:

```yaml
    permissions:
      contents: read
      security-events: write   # upload-sarif
      actions: read            # upload-sarif, private repositories only
    steps:
      - uses: actions/checkout@v4
      # ... install gooze, run (and merge) ...
      - name: Write SARIF
        run: gooze report view --format sarif --threshold-total 60 > gooze.sarif
      - name: Upload to code scanning
        if: ${{ !cancelled() }}         # also when the gate fails (exit 3)
        uses: github/codeql-action/upload-sarif@v4
        with:
          sarif_file: gooze.sarif
          category: gooze
```

- gooze writes the whole log before it checks thresholds, so `gooze.sarif` is
  complete even when the step exits 3.
- One result per line with survivors, under the rule `gooze/survived`,
  `gooze/not-covered`, `gooze/timeout` or `gooze/skipped` (the first that a
  mutant on the line has). `partialFingerprints` come from the line's mutation
  IDs, so an alert stays the same across runs while its mutants do.
- Job-level `permissions:` replaces the workflow's, so keep what the job
  already needs (`packages: write` for a GHCR push).
- Code scanning works on public repositories; private ones need GitHub Code
  Security or GitHub Advanced Security. Ask before suggesting it on a private
  repository.
