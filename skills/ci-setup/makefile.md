# Makefile target

Add a target next to `test`/`lint`, matching the file's style: recipe lines
start with a **tab**; reuse its `.PHONY` line, its echo/`@` style, and its
package variable if it has one (`PKGS`, `PKG_WHITELIST`, ...). gooze accepts
several paths, so a space-separated package list works as is.

```make
GOOZE_VERSION ?= v1.3.0
MUTATION_PKGS ?= ./...
# Extra gooze flags, e.g. MUTATION_FLAGS="-x mocks/ -x _gen\.go --mutation-timeout 300"
MUTATION_FLAGS ?=
MUTATION_PARALLEL ?= 4

.PHONY: install-gooze mutation mutation-report

install-gooze:
	GOTOOLCHAIN=auto go install gooze.dev/pkg/gooze@$(GOOZE_VERSION)

mutation:
	gooze run -p $(MUTATION_PARALLEL) $(MUTATION_FLAGS) $(MUTATION_PKGS)

mutation-report:
	gooze report view
```

Usage: `make mutation`, or scoped: `make mutation MUTATION_PKGS=./internal/foo/...`.

Adapt:

- **Existing package variable**: use it as the default,
  e.g. `MUTATION_PKGS ?= $(PKGS)`, instead of `./...`.
- **Tools installed into a local bin dir** (e.g. `bin := ./.bin` and
  `GOBIN=$(abspath $(bin)) go install ...`): install gooze the same way
  (`GOBIN=$(abspath $(bin)) GOTOOLCHAIN=auto go install gooze.dev/pkg/gooze@$(GOOZE_VERSION)`),
  call `$(bin)/gooze`, keep `GOOZE_VERSION` with the other `*_VERSION` pins,
  and add `install-gooze` to an existing `install-tools` aggregate.
- **Existing exclusions** in the `test` target (e.g. `grep -v /mocks`): mirror
  them as `-x` regexes (they match file paths), or put them in `gooze.yaml`
  under `paths.exclude` if that file exists.
- **Naming**: follow the file (`test-mutation`, `mutation-test`, `test.mutation`).
- **`clean` target**: add `rm -rf .gooze-reports` and `rm -f .gooze.log`.
- A literal `$` in a recipe or variable must be written `$$` (e.g. a regex anchor `_gen\.go$$`).
- Don't make `test` or `all` depend on `mutation`; it is much slower than tests.

If CI already calls `make test`/`make lint`, the CI job can call
`make install-gooze mutation` so both stay in sync.
