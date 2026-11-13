# k8s-release-chart

File: `.github/workflows/k8s-release-chart.yml` (reusable, `workflow_call`).

## What it does

An immutable, chart-aware release. It builds one multi-arch image `:X.Y.Z` (amd64 and arm64), packages the Helm chart as an
OCI artifact with the same version (the image tag is baked into the chart), pushes both to the registry, and bumps
`spec.sources[0].targetRevision` of the acc ArgoCD Application in the gitops repo. ArgoCD syncs acc from there.
The version comes from a `release/vX.Y.Z` branch, or is computed from Conventional Commits.

## Inputs

| Name | Required | Type | Default | Meaning |
|---|---|---|---|---|
| `project` | yes | string | | Harbor project |
| `app` | yes | string | | Image and chart name. The chart name in `Chart.yaml` must equal it |
| `dockerfile` | no | string | `Dockerfile` | Path to the Dockerfile |
| `context` | no | string | `.` | Build context |
| `chart_dir` | no | string | `chart` | Directory of the Helm chart |
| `registry` | no | string | `harbor.k8s-hotel.nl` | Registry host |
| `gitops_repo` | no | string | `git@github.com:globalcontrolgroup/gcg-shop-gitops.git` | SSH URL of the gitops repo |
| `gitops_app_file` | no | string | `""` | Application file whose `spec.sources[0].targetRevision` is bumped. Empty means `apps/acc/<app>.yaml` |
| `version_from` | no | string | `branch` | `branch` or `conventional` |

## Secrets

| Name | Required | Meaning |
|---|---|---|
| `gitops_deploy_key` | yes | SSH deploy key with write access to the gitops repo |
| `tag_deploy_key` | no | Write deploy key on the caller's app repo. Required when `version_from` is `conventional`; it pushes the computed `vX.Y.Z` tag |
| `npm_token` | no | Read token for a private package registry. Mounted into the build as the secret `npm_token` (Dockerfile: `--mount=type=secret,id=npm_token`). If not passed, `github.token` is used instead |

For the `github.token` fallback to read private GitHub Packages, the calling job must grant `permissions: packages: read` itself.
This workflow asks only for `contents: read`.

## Outputs

None. The step summary names the released version.

## How it works

Workflow settings: `permissions: contents: read`; `concurrency` group `release-<repository>` (one release at a time per app repo),
`cancel-in-progress: false`. Registry logins (`buildah login`, `helm registry login`) must be pre-stored on both the amd64 and
the arm64 runner.

Job `version` (`[self-hosted, harbor-builder]`). Outputs `version` and `released`.

1. Check out. History and tags are fetched fully only for `conventional`; `branch` uses a shallow checkout.
2. Derive the version.
   - `branch`: from the branch name `release/vMAJOR.MINOR.PATCH`; any other ref fails.
   - `conventional`: requires `tag_deploy_key`. Reads the latest `v*` tag (none means `v0.0.0`) and the commits since it.
     `type!:` or `BREAKING CHANGE` gives major, `feat` gives minor, `fix` gives patch. While major is 0, a breaking change bumps minor.
     With none of these, `released` is `false` and nothing else runs. Otherwise it pushes the annotated tag `vX.Y.Z` to the app repo
     with the deploy key (pinned `github.com` host key).
3. Validate `project` and `app` against `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`.
4. Guard: fail if the image `<registry>/<project>/<app>:<version>` or the chart `<registry>/<project>/charts/<app>:<version>` already exists.

Job `build` (`needs: version`, only when `released` is `true`): a matrix of two legs, `fail-fast: true`.

| Leg | `runs-on` |
|---|---|
| amd64 | `[self-hosted, harbor-builder]` |
| arm64 | `[self-hosted, harbor-builder-arm64]` |

Each leg checks out and runs `buildah bud --layers --isolation chroot` with the build args `APP_BUILD_SHA`, `APP_BUILD_TIME` and
`APP_BUILD_VERSION`, plus the `npm_token` secret when a token is available. It checks the image architecture, pushes by digest
without a tag, and writes the job output `digest_amd64` or `digest_arm64`.

Job `release` (`needs: [version, build]`, `[self-hosted, harbor-builder]`):

1. Check out. Join the two digests into a manifest list, push it as `:<version>`, and fail unless it lists exactly `amd64,arm64`.
2. Set `.image.tag` to the version in `<chart_dir>/values.yaml`, run `helm package --version <version> --app-version <version>`,
   and `helm push` to `oci://<registry>/<project>/charts`.
3. Clone the gitops repo with the deploy key (pinned `github.com` host key), set `.spec.sources[0].targetRevision` to the version in the
   Application file (`gitops_app_file`, or `apps/acc/<app>.yaml`), commit, and push. It fails if the file does not exist.
4. Summary. Prod is promoted with [k8s-promote](k8s-promote.md), a gitops PR and a manual Sync.

The image build here and in [build-multiarch](build-multiarch.md) are kept in sync.

## Example

```yaml
# .github/workflows/release.yml
name: release
on:
  push: { branches: ['release/v*'] }
jobs:
  release:
    uses: bizhostbv/actions/.github/workflows/k8s-release-chart.yml@v3
    with:
      project: myproject
      app: myapp
      gitops_repo: git@github.com:myorg/my-gitops.git
      gitops_app_file: apps/myapp/acceptance.yaml
    secrets:
      gitops_deploy_key: ${{ secrets.GITOPS_DEPLOY_KEY }}
      # npm_token: ${{ secrets.NPM_TOKEN }}
```
