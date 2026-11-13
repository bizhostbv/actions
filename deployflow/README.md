# deployflow

The shared deploy pipeline. One bash script, `deployflow/bin/deployflow`, implements it. The GitHub reusable
workflows and the GitLab template only set environment variables and call one subcommand.

Flow: merge to the default branch, version from conventional commits, image and chart in the registry, git tag,
acceptance bump in the gitops repo, then a manual production job that bumps production to the version acceptance runs.

| Part | File | Doc |
|---|---|---|
| Deploy to acceptance | `.github/workflows/deploy.yml` | [deploy](#deployyml) |
| Release to production | `.github/workflows/release-production.yml` | [release-production](#release-productionyml) |
| Pull request title check | `.github/workflows/pr-title.yml` | [pr-title](#pr-titleyml) |
| GitLab template | `gitlab/deploy.yml` | [gitlab/deploy](#gitlabdeployyml) |

## deploy.yml

### What it does

Runs on a push to the default branch (the caller sets the trigger). It computes the next version, builds the image for
amd64 and arm64, publishes the multi-arch image and the Helm chart, pushes the git tag, and bumps the acceptance
Application in the gitops repo. Each step runs only when the previous one succeeded and the commits since the last tag are
releasable. The git tag is pushed only after image and chart are in the registry, so a failed build never uses up a version.

### Inputs

| Name | Required | Type | Default | Meaning |
|---|---|---|---|---|
| `project` | yes | string | | Registry project |
| `app` | yes | string | | Image and chart name |
| `registry` | no | string | `registry.k8s-bizhost.nl` | Registry host |
| `dockerfile` | no | string | `Dockerfile` | Path to the Dockerfile |
| `context` | no | string | `.` | Build context |
| `chart_dir` | no | string | `chart` | Directory of the Helm chart |
| `gitops_repo` | yes | string | | `owner/name` on GitHub |
| `gitops_acc_file` | yes | string | | Application file whose `spec.sources[0].targetRevision` is bumped |

### Secrets

| Name | Required | Meaning |
|---|---|---|
| `app_id` | yes | Id of the GitHub App `deployflow` |
| `app_private_key` | yes | Private key of the GitHub App |
| `npm_token` | no | Mounted as build secret `id=npm_token`. If not passed, `github.token` is used |

### Outputs

None.

### How it works

Workflow settings: `permissions: contents: read`; `concurrency` group `deploy-<repository>`, `cancel-in-progress: false`;
`env.DEPLOYFLOW_REF` (see [DEPLOYFLOW_REF](#the-script-and-deployflow_ref)). Every job also checks out `bizhostbv/actions` at
`DEPLOYFLOW_REF` (sparse, only `deployflow`) into `.deployflow-src` and calls the script from there.

| Job | `runs-on` | Does |
|---|---|---|
| `version` | `[self-hosted, harbor-builder]` | Full-history checkout. `deployflow version` sets outputs `version` and `released`. If released, `deployflow guard-immutable` fails when image or chart already exist |
| `build` | amd64: `[self-hosted, harbor-builder]`, arm64: `[self-hosted, harbor-builder-arm64]` | Only when `released` is `true`. Matrix of two legs, `fail-fast: true`. `deployflow build` pushes the image by digest, untagged, and sets `digest_amd64` or `digest_arm64` |
| `publish` | `[self-hosted, harbor-builder]` | Creates an App token for the app repo and checks out with it. `deployflow publish` joins the digests into `:<version>`, packages the chart and pushes it. Then `deployflow push-tag` pushes the git tag |
| `gitops-acc` | `[self-hosted, harbor-builder]` | Splits `gitops_repo` into owner and name (must be `owner/name`), creates an App token for that repo, passes it to git as an auth header, runs `deployflow gitops-acc` |

The GitHub App must be installed on the app repo and the gitops repo, with `contents: write` on both. The runners need a registry
login stored on the host.

### Example

```yaml
# .github/workflows/deploy.yml
on: { push: { branches: [main] } }
jobs:
  deploy:
    uses: bizhostbv/actions/.github/workflows/deploy.yml@<release tag>
    with:
      project: myproject
      app: myapp
      gitops_repo: myorg/my-gitops
      gitops_acc_file: apps/myapp/acceptance.yaml
    secrets:
      app_id: ${{ secrets.DEPLOYFLOW_APP_ID }}
      app_private_key: ${{ secrets.DEPLOYFLOW_APP_PRIVATE_KEY }}
      # npm_token: ${{ secrets.NPM_TOKEN }}
```

## release-production.yml

### What it does

The production button. The caller exposes it as a `workflow_dispatch` with an optional `rollback` input and passes that input on.
The version is never typed in: it is the `targetRevision` of the acceptance Application, unless `rollback` names a former
production version. The guards are in `deployflow release-prod`: the actor is a member of the team `release-admins`, image and chart
exist, and the direction is right (forward, or backward for a rollback). Then it commits the version to the production Application file.

### Inputs

| Name | Required | Type | Default | Meaning |
|---|---|---|---|---|
| `project` | yes | string | | Registry project |
| `app` | yes | string | | Image and chart name |
| `registry` | no | string | `registry.k8s-bizhost.nl` | Registry host |
| `gitops_repo` | yes | string | | `owner/name` on GitHub |
| `gitops_acc_file` | yes | string | | Acceptance Application file |
| `gitops_prod_file` | yes | string | | Production Application file |
| `rollback` | no | string | `""` | A former production version to roll back to. Empty releases the acceptance version |

### Secrets

| Name | Required | Meaning |
|---|---|---|
| `app_id` | yes | Id of the GitHub App `deployflow` |
| `app_private_key` | yes | Private key of the GitHub App |

### Outputs

None.

### How it works

Workflow settings: `permissions: contents: read`; `concurrency` group `release-production-<repository>-<app>`,
`cancel-in-progress: false`; `env.DEPLOYFLOW_REF`. One job, `release`, on `[self-hosted, harbor-builder]`, which only runs when
`github.ref` is `refs/heads/main`. Steps:

1. Split `gitops_repo` into owner and name (must be `owner/name`).
2. Create an App token for the gitops repo. The App needs `contents: write` there and `Members: read` on the org.
3. Check out `bizhostbv/actions` at `DEPLOYFLOW_REF` (sparse, `deployflow` only).
4. Run `deployflow release-prod` with `DEPLOYFLOW_PROVIDER=github`, `ORG` set to the repository owner, and `ACTOR` set to
   `github.triggering_actor` (on a re-run this is the person re-running). The token goes to git as an auth header and to the script as
   `API_TOKEN` for the membership check.

### Example

```yaml
# .github/workflows/production.yml
on:
  workflow_dispatch:
    inputs:
      rollback:
        description: Former prod version to roll back to (empty = release acc)
        required: false
        default: ""
jobs:
  production:
    uses: bizhostbv/actions/.github/workflows/release-production.yml@<release tag>
    with:
      project: myproject
      app: myapp
      gitops_repo: myorg/my-gitops
      gitops_acc_file: apps/myapp/acceptance.yaml
      gitops_prod_file: apps/myapp/production.yaml
      rollback: ${{ inputs.rollback }}
    secrets:
      app_id: ${{ secrets.DEPLOYFLOW_APP_ID }}
      app_private_key: ${{ secrets.DEPLOYFLOW_APP_PRIVATE_KEY }}
```

## pr-title.yml

### What it does

Fails a pull request whose title is not a conventional commit. Pull requests are squash-merged, so the title becomes the commit
subject that decides the next version. Allowed types: `feat`, `fix`, `chore`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`,
`style`, `revert`, with an optional `(scope)` and an optional `!`, then `: ` and a subject.

### Inputs, secrets, outputs

None.

### How it works

Workflow settings: `permissions: contents: read`; `env.DEPLOYFLOW_REF`. One job, `title`, on `[self-hosted, harbor-builder]`:
check out `bizhostbv/actions` at `DEPLOYFLOW_REF` (sparse, `deployflow` only), then run `deployflow check-title` with `TITLE` set to the
pull request title.

### Example

```yaml
# .github/workflows/pr-title.yml
on: { pull_request: { types: [opened, edited, synchronize, reopened] } }
jobs:
  title:
    uses: bizhostbv/actions/.github/workflows/pr-title.yml@<release tag>
```

## gitlab/deploy.yml

### What it does

The same pipeline for GitLab, as a CI/CD component-style template (`spec: inputs`). Stages: `check`, `version`, `build`, `publish`,
`gitops`, `production`. A merge request runs the title check. A push to the default branch runs version, build (amd64 and arm64),
publish, and the acceptance bump, plus a manual production job. It uses the same script as the GitHub workflows, from the tool image
`registry.k8s-bizhost.nl/base/deployflow:<deployflow_version>`.

### Inputs

| Name | Required | Type | Default | Meaning |
|---|---|---|---|---|
| `project` | yes | string | | Registry project |
| `app` | yes | string | | Image and chart name |
| `registry` | no | string | `registry.k8s-bizhost.nl` | Registry host |
| `dockerfile` | no | string | `Dockerfile` | Path to the Dockerfile |
| `context` | no | string | `.` | Build context |
| `chart_dir` | no | string | `chart` | Directory of the Helm chart |
| `gitops_repo` | yes | string | | Clone URL of the gitops repo (not `owner/name`) |
| `gitops_acc_file` | yes | string | | Acceptance Application file |
| `gitops_prod_file` | yes | string | | Production Application file |
| `org` | yes | string | | GitLab group path that owns a subgroup `release-admins` |
| `deployflow_version` | yes | string | | Release tag of this repo; selects the tool image tag |

The inputs without a `default` in the template have no default.

### Secrets (CI/CD variables)

The consumer sets these as CI/CD variables (masked, protected where possible).

| Name | Required | Meaning |
|---|---|---|
| `DEPLOYFLOW_GITOPS_TOKEN` | yes | Write access to the gitops repo |
| `DEPLOYFLOW_TAG_TOKEN` | yes | Write access to the app repo (pushes the version tag) |
| `DEPLOYFLOW_API_TOKEN` | yes | Read access to the members of `<org>/release-admins` |
| `DEPLOYFLOW_REGISTRY_USER`, `DEPLOYFLOW_REGISTRY_PASSWORD` | no | Registry login, when the runner has none stored |
| `DEPLOYFLOW_NPM_TOKEN` | no | Mounted as build secret `id=npm_token` |

### Outputs

None. The `deployflow-version` job writes `version.env` and each build job a `digest_<arch>.env` as dotenv reports, so later jobs get
`released`, `version`, `digest_amd64` and `digest_arm64`.

### How it works

| Job | Stage | Runner tag | Does |
|---|---|---|---|
| `deployflow-check-title` | `check` | `harbor-builder` | Merge request pipelines only. `deployflow check-title` with the MR title |
| `deployflow-version` | `version` | `harbor-builder` | Default branch push. Full clone. `deployflow version`; if `released=true`, `guard-immutable` |
| `deployflow-build-amd64` | `build` | `harbor-builder` | `deployflow build` with `ARCH=amd64` |
| `deployflow-build-arm64` | `build` | `harbor-builder-arm64` | `deployflow build` with `ARCH=arm64` |
| `deployflow-publish` | `publish` | `harbor-builder` | `deployflow publish`, then points `origin` at the project URL with the tag token and runs `deployflow push-tag` |
| `deployflow-gitops-acc` | `gitops` | `harbor-builder` | `resource_group` per app. `deployflow gitops-acc` with the gitops token as auth header |
| `deployflow-release-production` | `production` | `harbor-builder` | Manual (`when: manual`, `allow_failure: true`), `resource_group` per app. `deployflow release-prod` with `DEPLOYFLOW_PROVIDER=gitlab` |

Build, publish and gitops jobs do nothing (exit 0) when the version job reported no release. Roll back by playing the manual job with the
variable `ROLLBACK=X.Y.Z` (a former production version).

### Example

```yaml
include:
  - remote: https://raw.githubusercontent.com/bizhostbv/actions/<tag>/gitlab/deploy.yml
    inputs:
      project: myproject
      app: myapp
      gitops_repo: https://gitlab.example.org/myorg/my-gitops.git
      gitops_acc_file: apps/myapp/acceptance.yaml
      gitops_prod_file: apps/myapp/production.yaml
      org: myorg
      deployflow_version: <tag>
```

Set the variables above in the project's CI/CD settings. The tag in the URL and `deployflow_version` must be the same release tag.

## The script and DEPLOYFLOW_REF

`deployflow/bin/deployflow` takes all input from environment variables. The full list is documented at the top of the script.
Main ones: `PROJECT`, `APP`, `REGISTRY`, `VERSION`, `ARCH`, `GIT_SHA`, `CHART_DIR`, `DIGEST_AMD64`, `DIGEST_ARM64`, `GITOPS_REPO`,
`GITOPS_ACC_FILE`, `GITOPS_PROD_FILE`, `RUN_URL`, `DEPLOYFLOW_OUTPUT` (a `key=value` file: `$GITHUB_OUTPUT` on GitHub, a dotenv file on
GitLab), `DEPLOYFLOW_PROVIDER` (`github` or `gitlab`), `ORG`, `ACTOR`, `ACTOR_ID`, `API_TOKEN`, `ROLLBACK`. Git authentication for the
gitops repo and the tag push is set up by the wrapper, never by the script.

| Subcommand | Does |
|---|---|
| `version` | Next `X.Y.Z` from commit subjects since the latest tag (`feat` minor, `fix` patch, `!` or `BREAKING CHANGE` major, while major is 0 a major becomes minor). Tags have no `v`; old `v` tags are read. It refuses when no `X.Y.Z` tag is reachable from HEAD: an existing app tags its current version on the commit it came from, a brand-new repo tags `0.0.0` once. Prints `none` and sets `released=false` when nothing is releasable |
| `push-tag` | Pushes tag `$VERSION` (creates it on HEAD if missing). Runs after `publish` |
| `check-title` | Fails unless `$TITLE` is a conventional commit title |
| `guard-immutable` | Fails if image or chart `$VERSION` already exists in the registry |
| `build` | Builds one `$ARCH` with buildah, checks the architecture, pushes by digest, writes `digest_<arch>=` |
| `publish` | Joins both digests into the manifest list `:$VERSION`, packages the chart with `image.tag=$VERSION` (runs `helm dependency build` when the chart has dependencies), pushes it |
| `gitops-acc` | Sets `targetRevision` in `$GITOPS_ACC_FILE`; skips (exit 0) when acceptance is already at or past `$VERSION`. Retries a rejected push up to 3 times with a rebase |
| `release-prod` | Guards: the actor is a member of `release-admins`; version is the acceptance `targetRevision` (or `$ROLLBACK`, which must be a former production version); image and chart exist; direction is forward (backward for a rollback). Then commits to `$GITOPS_PROD_FILE` |

`gitops-acc` and `release-prod` refuse an Application whose first source is not the OCI chart named `$APP`.

`DEPLOYFLOW_REF` is an `env` value in `deploy.yml`, `release-production.yml` and `pr-title.yml`. It is the ref of this repo from which the
workflow checks out the script. In a release it equals the release tag, so a caller pinned to a release tag also runs that release's script.

## The org provides

- A GitHub App `deployflow` with `contents: write` on the app and gitops repos and `Members: read` on the org; its id and private key as secrets.
- A team `release-admins` (a GitHub team in the org, or a GitLab subgroup of `$ORG`).
- Self-hosted runners labelled `harbor-builder` (amd64) and `harbor-builder-arm64`, with a registry login stored, or `DEPLOYFLOW_REGISTRY_*` on GitLab.
- `main` protected, squash merge, and the pull request or merge request title check required.

## Tool image

`deployflow/Dockerfile` builds the tool image for GitLab (and anywhere else the script runs in a container). It is based on
`quay.io/buildah/stable`, adds `skopeo`, `helm`, `jq`, `curl`, `git` and mikefarah `yq` (the build needs `--build-arg YQ_SHA256=<sha256 of the yq binary>`),
sets `STORAGE_DRIVER=vfs` and `BUILDAH_ISOLATION=chroot`, and copies the script to `/usr/local/bin/deployflow`. Publish it under the same tag as the release:

```
docker build -f deployflow/Dockerfile --build-arg YQ_SHA256=<sha256> -t <registry>/base/deployflow:<tag> .
```

## Releasing

Tags follow this repo's scheme: an annotated `vX.Y.Z` plus the moving major tag `vX`. The release pull request sets `DEPLOYFLOW_REF` to
the new tag in `deploy.yml`, `release-production.yml` and `pr-title.yml` (the tests fail if they differ or name a branch). Tag the merge
commit after the merge.

## Tests

```
bash deployflow/test/run.sh
```

Needs `git`, `yq` (mikefarah v4) and `jq` on the host. No network and no framework: `skopeo`, `buildah`, `helm` and `curl` are stubs on `PATH`,
and `git` talks to local bare repositories. The script works on bash 3.2 and bash 5.
