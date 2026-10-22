# Task runners and other CI systems

Same rules: only a file that exists, snippet shown first, edit on a yes.

## Taskfile (`Taskfile.yml`)

Add under the existing `tasks:`, copying its indentation, `desc:` style and
any shared `vars:` (e.g. a package list):

```yaml
  install-gooze:
    desc: Install gooze
    cmds:
      - GOTOOLCHAIN=auto go install gooze.dev/pkg/gooze@v1.3.0

  mutation:
    desc: Run gooze mutation testing (task mutation -- ./internal/foo/...)
    cmds:
      - gooze run -p 4 {{if .CLI_ARGS}}{{.CLI_ARGS}}{{else}}./...{{end}}
```

## justfile

Copy the file's indentation (spaces or tabs, consistently) and recipe style:

```just
gooze_version := "v1.3.0"

install-gooze:
    GOTOOLCHAIN=auto go install gooze.dev/pkg/gooze@{{gooze_version}}

# Run gooze mutation testing: just mutation ./internal/foo/...
mutation *paths="./...":
    gooze run -p 4 {{paths}}
```

## Mage (`magefile.go`)

Only if the file already imports `github.com/magefile/mage/sh`; add a target
in the same file:

```go
// Mutation runs gooze mutation testing.
func Mutation() error {
	return sh.RunV("gooze", "run", "-p", "4", "./...")
}
```

## Other CI (CircleCI, Bitbucket Pipelines, Azure Pipelines, Jenkins, Woodpecker, Drone)

Add one job/step to the existing config using its Go image/toolchain setup and
its trigger style (PRs + default branch). The shell steps are the same
everywhere:

```sh
GOTOOLCHAIN=auto go install gooze.dev/pkg/gooze@v1.3.0
gooze report pull "$REPORTS_REF" || echo "no baseline yet"   # optional OCI baseline
gooze run -p 4 ./...
gooze report view
# default branch only, optional: gooze report push "$REPORTS_REF"
```

Or cache `.gooze-reports/` with the system's own cache feature (key per
branch, falling back to the default branch). Sharding: run
`gooze run -s INDEX/TOTAL` (0-based INDEX) in parallel jobs, bring every
`.gooze-reports/shard_*` dir into one `.gooze-reports/`, then
`gooze report merge`. Registry auth: `GOOZE_REGISTRY_USERNAME` /
`GOOZE_REGISTRY_PASSWORD` from the CI's secret store. If unsure of a CI
system's syntax for caching or parallelism, give the shell steps and say which
part the user should map to their config.

## Not recommended

- `.pre-commit-config.yaml`, lefthook, husky, git hooks: a gooze run takes
  minutes; commit hooks must take seconds. Use a Make/task target instead.
- `go generate` directives, `Dockerfile` builds: not a place for test runs.
