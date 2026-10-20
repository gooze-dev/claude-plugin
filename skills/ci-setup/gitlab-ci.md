# GitLab CI

Add a job to the **existing** `.gitlab-ci.yml` (or to the included file that
holds the Go jobs). Copy its conventions: the `image:` (global or per job; reuse
its `golang:X` tag), `stages:` (reuse `test`, or add a stage to the list; a job
whose stage isn't listed is an error), `tags:`, `before_script:`, `variables:`
(e.g. a `GOPATH` under `$CI_PROJECT_DIR`), the existing Go module `cache:`, and
`workflow:rules` / job `rules:` style.

`GOTOOLCHAIN=auto` matters here: official `golang:*` images set
`GOTOOLCHAIN=local`, and gooze v1.1.1 needs Go >= 1.27.3 to build. If the repo
relocates `GOPATH`, `gooze` lands in `$GOPATH/bin`; call it by that path (or
add it to `PATH`) unless that dir is already on `PATH`.

## Rules

Run on merge requests and the default branch (which refreshes the cache), not
on every branch push. Match how the pipeline already runs:
- MR pipelines already used (`merge_request_event` in `workflow:rules` or job
  rules): `- if: $CI_PIPELINE_SOURCE == "merge_request_event"` and
  `- if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH` (as below).
- Branch pipelines only: the same rules work, but a push to an MR branch then
  starts a second (MR) pipeline holding just this job. Mention it; the
  alternative is `- if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH` plus
  `- if: $CI_COMMIT_BRANCH` with `when: manual`.
- Optional nightly full re-test: a pipeline schedule,
  `- if: $CI_PIPELINE_SOURCE == "schedule"`, running `gooze run --no-cache`.

## 1. Single job with cache (recommended start)

```yaml
mutation:
  stage: test
  timeout: 1h
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
  cache:
    - key: gooze-$CI_COMMIT_REF_SLUG
      fallback_keys:
        - gooze-$CI_DEFAULT_BRANCH
      paths:
        - .gooze-reports/
  script:
    - GOTOOLCHAIN=auto go install gooze.dev/pkg/gooze@v1.1.1
    - gooze run -p 4 ./...
    - gooze report view
  artifacts:
    when: always
    expire_in: 1 week
    paths:
      - .gooze-reports/
```

- A job-level `cache:` **replaces** the global one. If the file has a global
  Go module cache the job should keep, list both entries under the job's
  `cache:` (it accepts a list).
- `fallback_keys` (GitLab 16.0+) lets an MR branch start from the default
  branch's reports. Caches are per runner unless distributed cache is set up;
  a miss only means a full run.
- If a `mutation` Make target exists, `- make install-gooze mutation`.

## 2. Sharded with `parallel:`

`CI_NODE_INDEX` is **1-based**, gooze shards are **0-based**:

```yaml
mutation:
  stage: test
  parallel: 4
  cache:
    - key: gooze-$CI_COMMIT_REF_SLUG
      fallback_keys: [gooze-$CI_DEFAULT_BRANCH]
      paths: [.gooze-reports/]
      policy: pull               # shards only read; the merge job writes
  script:
    - GOTOOLCHAIN=auto go install gooze.dev/pkg/gooze@v1.1.1
    - gooze run -p 2 -s "$((CI_NODE_INDEX - 1))/$CI_NODE_TOTAL" ./...
  artifacts:
    paths:
      - .gooze-reports/shard_*/

mutation-merge:
  stage: mutation-merge        # add after the shards' stage in `stages:`
  needs: [mutation]            # downloads every parallel instance's artifacts
  cache:
    - key: gooze-$CI_COMMIT_REF_SLUG
      fallback_keys: [gooze-$CI_DEFAULT_BRANCH]
      paths: [.gooze-reports/]
  script:
    - GOTOOLCHAIN=auto go install gooze.dev/pkg/gooze@v1.1.1
    - gooze report merge
    - gooze report view
  artifacts:
    when: always
    paths:
      - .gooze-reports/
```

Give both jobs the same `rules:`. Gate only in the merge job.

## 3. Baseline in the GitLab container registry (optional)

Shared with teammates and independent of runner caches. Instead of `cache:`:

```yaml
variables:
  REPORTS_REF: "$CI_REGISTRY_IMAGE/gooze-reports:main"
  GOOZE_REGISTRY_USERNAME: "gitlab-ci-token"
  GOOZE_REGISTRY_PASSWORD: "$CI_JOB_TOKEN"
```

Before `gooze run` (every shard, and the merge job before `gooze report merge`):
`- gooze report pull "$REPORTS_REF" || echo "no baseline yet"`.
After the run/merge, default branch only:

```yaml
    - |
      if [ "$CI_COMMIT_BRANCH" = "$CI_DEFAULT_BRANCH" ]; then
        gooze report push "$REPORTS_REF"
      fi
```

Put these variables on the mutation jobs if the global `variables:` would leak
the token setting into unrelated jobs. The registry must be enabled for the
project.

## Score gate (optional)

gooze has no threshold flag. Append to the script of the single job (or the
merge job):

```yaml
  variables:
    MIN_SCORE: "60"
  script:
    # ...after gooze run / gooze report merge
    - |
      score=$(gooze report view | sed -n 's/^Mutation score: \([0-9.]*\)%$/\1/p' | tail -1)
      echo "Mutation score: ${score}% (minimum ${MIN_SCORE}%)"
      awk -v s="$score" -v m="$MIN_SCORE" 'BEGIN { exit !(s != "" && s >= m) }'
```

The cache is saved only when the job succeeds (cache `when:` defaults to
`on_success`); add `when: always` to the gooze cache entry so a failed gate
still keeps the reports.
