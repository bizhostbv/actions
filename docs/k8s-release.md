# k8s-release

File: `.github/workflows/k8s-release.yml` (reusable, `workflow_call`).

## What it does

An immutable image release for a container app. A push to `release/vX.Y.Z` builds one multi-arch image
`:X.Y.Z` (amd64 and arm64), pushes it to the registry, and writes the tag into a values file in the gitops
repo on `main` (acc). ArgoCD syncs acc from there. There are no moving tags. There is no chart: the gitops
repo holds the values. For a chart-based release see [k8s-release-chart](k8s-release-chart.md).

## Inputs

| Name | Required | Type | Default | Meaning |
|---|---|---|---|---|
| `project` | yes | string | | Harbor project |
| `app` | yes | string | | Image and app name |
| `dockerfile` | no | string | `Dockerfile` | Path to the Dockerfile |
| `context` | no | string | `.` | Build context |
| `build_args` | no | string | `''` | Space-separated `KEY=VALUE` pairs |
| `registry` | no | string | `''` | Registry host. Empty means the repository variable `HARBOR_REGISTRY` |
| `gitops_repo` | no | string | `git@github.com:bizhostbv/k8s-hotel-cluster-gitops.git` | SSH URL of the gitops repo |
| `values_file` | no | string | `''` | Values file to edit. Empty means `values/acc/<app>.yaml` |
| `tag_key` | no | string | `.image.tag` | `yq` path of the image tag to set |

## Secrets

| Name | Required | Meaning |
|---|---|---|
| `gitops_deploy_key` | yes | SSH deploy key with write access to the gitops repo |
| `harbor_username` | yes | Registry robot user |
| `harbor_token` | yes | Registry robot token |

## Outputs

None. The step summary names the released image.

## How it works

Workflow settings: `concurrency` group `release-<repository>-<app>` (matrix services can run side by side,
the same app is serialized), `cancel-in-progress: false`. No `permissions` block is set.

Job `version` (`[self-hosted, harbor-builder]`):

1. Check out. Resolve the registry (`registry` input, else `vars.HARBOR_REGISTRY`; fail if both are empty).
2. Take the version from the branch name `release/vMAJOR.MINOR.PATCH` and fail for any other branch.
   Outputs: `version`, `registry`, `image` (`<registry>/<project>/<app>:<version>`).
3. Guard: `skopeo inspect` with the robot credentials; fail if the image already exists.

Job `build` (`needs: version`): a matrix of two legs, `fail-fast: true`.

| Leg | `runs-on` |
|---|---|
| amd64 | `[self-hosted, harbor-builder]` |
| arm64 | `[self-hosted, harbor-builder-arm64]` |

Each leg checks out, builds with `buildah bud --layers --isolation chroot`, checks that the image architecture matches the
leg, and pushes by digest without a tag (OCI layout, then `skopeo copy --preserve-digests`). The digest goes to the job output
`digest_amd64` or `digest_arm64`.

Job `release` (`needs: [version, build]`, `[self-hosted, harbor-builder]`):

1. Join the two digests into a manifest list, push it as `:<version>`, and fail unless it lists exactly `amd64,arm64`.
2. Write the tag into the gitops repo: clone, then up to 5 attempts of fetch, reset to `origin/main`, set `tag_key` to the version with
   `yq` (downloads `yq` when it is not installed), commit `release(acc/<app>): <version>`, push to `main`. A rejected push is retried after
   a short random sleep. If the tag is already set, nothing is committed. Fails when all attempts fail. The host key is accepted on first use.
3. Summary line. Prod is promoted by a reviewed gitops PR, see [k8s-promote](k8s-promote.md).

## Example

```yaml
# .github/workflows/release.yml
name: release
on:
  push: { branches: ['release/v*'] }
jobs:
  release:
    uses: bizhostbv/actions/.github/workflows/k8s-release.yml@v3
    with:
      project: myproject
      app: myapp
    secrets:
      gitops_deploy_key: ${{ secrets.GITOPS_DEPLOY_KEY }}
      harbor_username: ${{ secrets.HARBOR_USERNAME }}
      harbor_token: ${{ secrets.HARBOR_TOKEN }}
```
