---
name: ci-setup
description: Set up gooze mutation testing in a Go project's build and CI - recommend adding it to the EXISTING Makefile, GitHub Actions workflows, .gitlab-ci.yml, Taskfile, justfile or other CI config, with a snippet adapted to that file, applied only after the user agrees. Never creates a new CI file or Makefile.
when_to_use: Use when the user asks to set up mutation testing for a project that has a Makefile or CI config, to add mutation testing or gooze to CI, a pipeline, a workflow, a Makefile or a task runner, to run gooze on pull requests, to shard gooze or cache its reports in CI, to gate on a mutation score, or asks what to do next after a successful local gooze run.
allowed-tools: Read Glob Grep
---

# Add gooze to the project's existing build and CI files

Goal: wire `gooze run` into files the project **already has**. You recommend,
show the exact snippet, and edit only after the user says yes.

## Hard rules

- **Only existing files.** Never create a Makefile, workflow, `.gitlab-ci.yml`,
  Taskfile or any other CI/build file, even if asked "set up CI". If none
  exists, say so, give the local commands (`gooze run ./...`,
  `gooze report view`), and offer the gooze.dev CI guides as something the user
  can add themselves: <https://gooze.dev/docs/ci/github>,
  <https://gooze.dev/docs/ci/gitlab>.
- **No edit without agreement.** First show the file path, where the snippet
  goes, and the snippet, then **end your turn with the question** ("Add this
  to `<file>`?"). Don't call Edit/Write in that turn, even if it's permitted;
  "set it up" or "add it to CI" is not yet a yes to a snippet the user hasn't
  seen. Apply only after an explicit yes. One file at a time.
- **Not in pre-commit hooks** (`.pre-commit-config.yaml`, lefthook, husky):
  a run takes minutes (one `go test` per mutant), far too slow for a commit
  hook. Say this if the user asks for it.
- Use only real gooze commands and flags (listed below). Don't invent a
  threshold flag: gooze has none, and survivors never change its exit code.

## 1. Detect (Glob, then Read)

Glob the repo root for:

| Kind | Patterns | Reference |
|---|---|---|
| Make | `Makefile`, `GNUmakefile`, `makefile`, `*.mk` | [makefile.md](makefile.md) |
| GitHub Actions | `.github/workflows/*.yml`, `.github/workflows/*.yaml` | [github-actions.md](github-actions.md) |
| GitLab CI | `.gitlab-ci.yml`, plus files it `include:`s | [gitlab-ci.md](gitlab-ci.md) |
| Task runners | `Taskfile.yml`, `Taskfile.yaml`, `taskfile.yml`, `justfile`, `Justfile`, `.justfile`, `magefile.go` | [other.md](other.md) |
| Other CI | `.circleci/config.yml`, `bitbucket-pipelines.yml`, `azure-pipelines.yml`, `Jenkinsfile`, `.woodpecker.yml`, `.drone.yml` | [other.md](other.md) |

Also check `go.mod` (module root, `go` line), the gooze marker in `CLAUDE.md` / `AGENTS.md` (Grep `gooze:begin`), `gooze.yaml` (exclusions and
parallelism already configured there need not be repeated as flags),
`.gitignore`, and whether a mutation target/job already exists (then improve
it rather than adding a second one).

Read only the reference file for the kinds you found.

## 2. Read the file's conventions

Before writing a snippet, note: indentation (tabs in Makefiles; 2 or 4 spaces
in YAML, list style `- uses` vs indented), naming (`test-unit`, `test:race`),
existing package/path variables (`PKGS`, `PKG_WHITELIST`), how tools are
installed (`go install` into `./.bin`, a `tools.go`, pinned `*_VERSION`
variables), the Go setup (`actions/setup-go` with `go-version`/`go-version-file`,
a `golang:X` container/image), cache steps, runner/tags, triggers,
`stages:` and `workflow:rules`. Copy them. Reuse the Go version the file
already uses; never introduce a different one.

## 3. Recommend

Suggest the smallest useful change first, then mention the optional upgrades:

1. **Make/task target** `mutation` (or the file's naming style) so humans and CI
   run the same command.
2. **CI job on pull requests** (and optionally a nightly schedule on the
   default branch), not on every push to every branch.
3. Optional: **cache** `.gooze-reports/` so a PR only re-tests changed files.
4. Optional: **sharding** across parallel jobs for large repos.
5. Optional: **score gate** (shell check on `gooze report view`, see the CI
   references) once the team has a baseline score to defend.

Explain the cost honestly: every mutant runs that package's tests, so a full
`./...` run can take many minutes to hours. Mitigations: scope paths, exclude
generated code/mocks with `-x`, `-p N` workers, the incremental cache, sharding,
`--mutation-timeout` for slow suites. Gooze re-tests a file only if it, its
`_test.go` file, or the mutators changed, so with a cached baseline a PR run is
usually small. The cache does not see cross-file test dependencies; a nightly
`--no-cache` run on the default branch refreshes it.

## Install line (all targets)

```sh
GOTOOLCHAIN=auto go install gooze.dev/pkg/gooze@v1.2.0
```

- **Pin a version** in CI so a new gooze release can't change results or
  break the pipeline unannounced; bump it deliberately. `@latest` is fine for
  a quick local try. Which version: if `CLAUDE.md` or `AGENTS.md` has a
  `<!-- gooze:begin guide=N gooze=vX.Y.Z -->` marker (written by `/gooze:init`),
  pin that `vX.Y.Z` so local, CI and the guide agree; otherwise `v1.2.0`, the
  current release. Snippets in the reference files say `v1.2.0`; substitute.
- **`GOTOOLCHAIN=auto`**: gooze v1.2.0 needs Go >= 1.27.3 to build. Official
  `golang:*` images set `GOTOOLCHAIN=local`, so on an older image the plain
  install fails with "requires go >= 1.27.3". With `auto`, Go fetches the newer
  toolchain just to build gooze; the project's tests still run on its own Go.
  Keep it unless the project already uses Go >= 1.27.3.

## gooze commands you may use

`gooze run [paths...]` (default `./...`) with `-p N`, `-s INDEX/TOTAL`
(0-based, `0 <= INDEX < TOTAL`; writes `.gooze-reports/shard_INDEX/`),
`--estimate`, `--mutation-timeout SEC` (default 120), `--coverage-profile FILE`,
`-x REGEX` (repeatable), `-o DIR` (default `.gooze-reports`), `--no-cache`.
`gooze report view` (prints `Mutation score: NN.NN% (…)` last; v1.2.0 adds the breakdown in parentheses),
`gooze report merge` (combines `shard_*`), `gooze report push <ref>` /
`gooze report pull <ref>` (OCI registry; auth via `GOOZE_REGISTRY_USERNAME` /
`GOOZE_REGISTRY_PASSWORD` or the Docker credential store; `--plain-http`,
`--insecure`). `gooze config init`, `gooze version`.

Suggest adding `.gooze-reports/` and `.gooze.log` to an existing `.gitignore`
and to an existing `clean` target, if not there.

## 4. Apply on approval

After a yes: edit exactly what you showed, then re-read the file to check
indentation and YAML structure. For a Makefile target, offer to run
`make -n mutation` (dry run) to confirm it parses. Don't commit.
