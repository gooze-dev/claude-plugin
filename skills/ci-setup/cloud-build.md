# Google Cloud Build

Add a step (or a few) to the **existing** build config: `cloudbuild.yaml`,
`cloudbuild.yml`, `cloudbuild.json` or a variant such as `cloudbuild-ci.yaml`
that the repo's triggers use. If several exist, pick the one that runs
`go test` (ask when unclear). Don't create a new config or trigger.

Copy from the file:
- **Step style.** `script:` steps or `entrypoint:` + `args:`. A new `script:`
  step is fine next to `args:` steps, but don't convert existing steps.
- **The Go image** the test step already uses (`golang:X`, or a custom image
  with Go). Reuse its tag; never introduce a different Go version.
- **`options:`** (`machineType`, `pool`, `logging`, `env`, `volumes`) and
  `timeout:`, `substitutions:`, `availableSecrets:`. Merge into them; don't add
  a second `options:` block.
- **JSON configs** take the same keys; write the snippet as JSON.

`GOTOOLCHAIN=auto` matters: official `golang:*` images set
`GOTOOLCHAIN=local`, and gooze v1.2.0 needs Go >= 1.27.3 to build.

## Things specific to Cloud Build

- **Timeout.** The build default is 60 minutes (maximum 24 hours). A run
  starts one `go test` per mutant; if a full run may take longer, set a
  top-level `timeout:` (e.g. `7200s`) or raise the existing one, and say why.
- **Parallelism: `-p`, not shards.** Every step of a build runs on one machine,
  so parallel `-s INDEX/TOTAL` steps only share its CPUs. Use `-p N` with N =
  the machine's vCPUs; suggest a bigger `machineType` (`E2_HIGHCPU_8`,
  `E2_HIGHCPU_32`) for large repos. If `options.pool` names a private pool, the
  pool sets the machine: don't add `machineType`.
- **Steps share only `/workspace`.** A binary installed in one step is gone in
  the next unless a volume keeps `/go`. Keep install and run in one step, or
  add the `go` volume below when later steps call `gooze`.
- **Substitutions in `script:`** need `options.automapSubstitutions: true`;
  then `PROJECT_ID`, `BRANCH_NAME`, `_PR_NUMBER` and user `_VARS` are
  environment variables. In `args:` steps, Cloud Build substitutes `$VAR`
  itself, so shell variables must be written `$$VAR`.
- **Pull requests vs `main`.** PR-trigger builds set `_PR_NUMBER`; push
  builds don't. Push a baseline only when `_PR_NUMBER` is empty and
  `BRANCH_NAME` is the default branch.
- Triggers live in the Cloud Build console (or `gcloud builds triggers`), not
  in the repo: tell the user which triggers should run the config (PRs into
  the default branch, pushes to it); don't create them.

## 1. One step (recommended start)

```yaml
steps:
  # ...existing steps
  - id: mutation
    name: golang:1.27              # the image the test step uses
    script: |
      GOTOOLCHAIN=auto go install gooze.dev/pkg/gooze@v1.2.0
      gooze run -p 8 ./...
      gooze report view

timeout: 7200s
options:
  machineType: E2_HIGHCPU_8
```

If a `mutation` Make target exists, run `make install-gooze mutation` instead.
For an `args:`-style file:
`entrypoint: sh`, `args: ['-c', 'GOTOOLCHAIN=auto go install gooze.dev/pkg/gooze@v1.2.0 && gooze run -p 8 ./...']`.

## 2. Baseline in Artifact Registry (optional)

Pull requests then re-test only changed files. Container Registry
(`gcr.io`) is shut down; Artifact Registry replaces it (it also serves
`gcr.io` repositories) and stores gooze's OCI report artifact in a
Docker-format repository. One-time setup the user runs (show it, don't run it):

```sh
gcloud artifacts repositories create gooze --repository-format=docker \
  --location=REGION --description="gooze mutation reports"
gcloud artifacts repositories add-iam-policy-binding gooze --location=REGION \
  --member="serviceAccount:BUILD_SERVICE_ACCOUNT" --role=roles/artifactregistry.writer
```

`BUILD_SERVICE_ACCOUNT` is the trigger's service account (projects whose
first build ran after mid-2024: the Compute Engine default,
`PROJECT_NUMBER-compute@developer.gserviceaccount.com`; earlier projects:
`PROJECT_NUMBER@cloudbuild.gserviceaccount.com`).

Steps (the token lasts about an hour, so fetch a fresh one before the push):

```yaml
steps:
  - id: registry-token
    name: gcr.io/cloud-builders/gcloud
    script: gcloud auth print-access-token > /registry/token

  - id: mutation
    name: golang:1.27
    script: |
      set -e
      GOTOOLCHAIN=auto go install gooze.dev/pkg/gooze@v1.2.0
      export GOOZE_REGISTRY_USERNAME=oauth2accesstoken
      export GOOZE_REGISTRY_PASSWORD="$(cat /registry/token)"
      REPORTS_REF="${_REGION}-docker.pkg.dev/${PROJECT_ID}/gooze/reports:main"
      gooze report pull "$REPORTS_REF" || echo "no baseline yet"
      gooze run -p 8 ./...
      gooze report view

  - id: push-token
    name: gcr.io/cloud-builders/gcloud
    script: gcloud auth print-access-token > /registry/token

  - id: push-baseline
    name: golang:1.27
    script: |
      set -e
      if [ -n "${_PR_NUMBER:-}" ] || [ "$BRANCH_NAME" != main ]; then exit 0; fi
      export GOOZE_REGISTRY_USERNAME=oauth2accesstoken
      export GOOZE_REGISTRY_PASSWORD="$(cat /registry/token)"
      gooze report push "${_REGION}-docker.pkg.dev/${PROJECT_ID}/gooze/reports:main"

substitutions:
  _REGION: us-central1

timeout: 7200s
options:
  machineType: E2_HIGHCPU_8
  automapSubstitutions: true
  volumes:                         # shared by every step
    - name: go                     # keeps the installed gooze for the push step
      path: /go
    - name: registry               # the token, outside the source tree
      path: /registry
```

Replace `main` with the repo's default branch. If the file already sets
`options.volumes`, add these entries to it. A trigger running as a
user-managed service account also needs `options.logging` (for example
`CLOUD_LOGGING_ONLY`); keep whatever the file has.

## Score gate (optional)

gooze has no threshold flag. Append to the `mutation` step's script, with
`_MIN_SCORE: "60"` under `substitutions:` (needs `automapSubstitutions`):

```yaml
      score=$(gooze report view | sed -n 's/^Mutation score: \([0-9.]*\)%.*$/\1/p' | tail -1)
      echo "Mutation score: ${score}% (minimum ${_MIN_SCORE}%)"
      awk -v s="$score" -v m="$_MIN_SCORE" 'BEGIN { exit !(s != "" && s >= m) }'
```

A failing gate stops the build before `push-baseline`, so a `main` build
below the minimum doesn't publish its baseline.

Full walkthrough for the user: <https://gooze.dev/docs/ci/cloud-build>.
