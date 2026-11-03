# deployflow

One bash script (`bin/deployflow`) implements the deploy pipeline; the GitHub reusable workflows and
the GitLab template only set env vars and call a subcommand. Flow: merge to the default branch,
version from conventional commits, image + chart in the registry, git tag, acceptance bump in the
gitops repo, then a manual production job that bumps production to the version acceptance runs.

## Subcommands
| Command | Does |
|---|---|
| `version` | Next X.Y.Z from commit subjects since the latest tag (feat minor, fix patch, `!`/BREAKING CHANGE major, 0.x major becomes minor). Tags have no `v`; old `v` tags are read. Prints `none` and `released=false` when nothing is releasable. |
| `push-tag` | Pushes tag `$VERSION` (creates it on HEAD if missing). Runs after `publish`. |
| `check-title` | Fails unless `$TITLE` is a conventional commit title. |
| `guard-immutable` | Fails if image or chart `$VERSION` already exists in the registry. |
| `build` | Builds one `$ARCH` with buildah, checks the arch, pushes by digest, writes `digest_<arch>=`. |
| `publish` | Joins both digests into manifest list `:$VERSION`, packages the chart with `image.tag=$VERSION`, pushes it. |
| `gitops-acc` | Sets `targetRevision` in `$GITOPS_ACC_FILE`; skips (exit 0) when acc is already at or past `$VERSION`. |
| `release-prod` | Guards: member of `release-admins`; version = acc `targetRevision` (or `$ROLLBACK`, which must be a former prod version); image and chart exist; direction (forward, or backward for rollback). Then commits to `$GITOPS_PROD_FILE`. |

## Environment
All input is env. The full list is documented at the top of `bin/deployflow`. Main ones: `PROJECT`,
`APP`, `REGISTRY`, `VERSION`, `ARCH`, `GIT_SHA`, `CHART_DIR`, `DIGEST_AMD64`, `DIGEST_ARM64`,
`GITOPS_REPO`, `GITOPS_ACC_FILE`, `GITOPS_PROD_FILE`, `RUN_URL`, `DEPLOYFLOW_OUTPUT` (key=value file),
`DEPLOYFLOW_PROVIDER` (`github`|`gitlab`), `ORG`, `ACTOR`, `ACTOR_ID`, `API_TOKEN`, `ROLLBACK`.
Git auth for the gitops repo and the tag push is set up by the wrapper, never by the script.

## GitHub
```yaml
# .github/workflows/deploy.yml
on: { push: { branches: [main] } }
jobs:
  deploy:
    uses: bizhostbv/actions/.github/workflows/deploy.yml@<release tag>
    with: { project: myproject, app: myapp, gitops_repo: myorg/my-gitops, gitops_acc_file: apps/myapp/acceptance.yaml }
    secrets: { app_id: "${{ secrets.DEPLOYFLOW_APP_ID }}", app_private_key: "${{ secrets.DEPLOYFLOW_APP_PRIVATE_KEY }}" }
# .github/workflows/production.yml
on: { workflow_dispatch: { inputs: { rollback: { required: false, default: "" } } } }
jobs:
  production:
    uses: bizhostbv/actions/.github/workflows/release-production.yml@<release tag>
    with: { project: myproject, app: myapp, gitops_repo: myorg/my-gitops, gitops_acc_file: apps/myapp/acceptance.yaml, gitops_prod_file: apps/myapp/production.yaml, rollback: "${{ inputs.rollback }}" }
    secrets: { app_id: "${{ secrets.DEPLOYFLOW_APP_ID }}", app_private_key: "${{ secrets.DEPLOYFLOW_APP_PRIVATE_KEY }}" }
# .github/workflows/pr-title.yml
on: { pull_request: { types: [opened, edited, synchronize, reopened] } }
jobs: { title: { uses: bizhostbv/actions/.github/workflows/pr-title.yml@<release tag> } }
```

## GitLab
```yaml
include:
  - remote: https://raw.githubusercontent.com/bizhostbv/actions/<tag>/gitlab/deploy.yml
    inputs: { project: myproject, app: myapp, gitops_repo: "https://gitlab.example.org/myorg/my-gitops.git", gitops_acc_file: ..., gitops_prod_file: ..., org: myorg, deployflow_version: <tag> }
```
Variables are listed in the header of `gitlab/deploy.yml`. Roll back by playing the manual job with `ROLLBACK=X.Y.Z`.
Tool image: `deployflow/Dockerfile`, published as `base/deployflow:<tag>`.

## The org provides
- GitHub App "deployflow" with contents: write on the app and gitops repos and Members: read on the org; its id and private key as secrets.
- A group/team `release-admins` (GitHub team in the org, GitLab subgroup of `$ORG`).
- Self-hosted runners labelled `harbor-builder` (amd64) and `harbor-builder-arm64`, with registry login stored, or `DEPLOYFLOW_REGISTRY_*` on GitLab.
- `main` protected, squash merge, PR/MR title check required.

## Tests
`bash deployflow/test/run.sh` (needs git, yq v4, jq; stubs replace skopeo, buildah, helm, curl).
