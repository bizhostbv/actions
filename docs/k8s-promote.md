# k8s-promote

File: `.github/workflows/k8s-promote.yml` (reusable, `workflow_call`).

## What it does

Promotes an image and chart that already exist on the acc registry to the prod registry, and stages the
prod bump in the gitops repo. The image is copied with the same digest, without a rebuild.
It never deploys: a person opens and merges the gitops PR and, unless the prod Application auto-syncs, clicks Sync in ArgoCD.

## Inputs

| Name | Required | Type | Default | Meaning |
|---|---|---|---|---|
| `project` | yes | string | | Registry project |
| `app` | yes | string | | Image and chart name |
| `version` | yes | string | | `X.Y.Z`, must already exist on the acc registry |
| `acc_registry` | no | string | `harbor.k8s-hotel.nl` | Source registry |
| `prod_registry` | no | string | `registry.k8s-bizhost.nl` | Destination registry |
| `gitops_repo` | no | string | `git@github.com:globalcontrolgroup/gcg-shop-gitops.git` | SSH URL of the gitops repo |
| `gitops_app_file` | no | string | `""` | Path of the prod ArgoCD Application in the gitops repo. Empty means `apps/prod/<app>.yaml` |

## Secrets

| Name | Required | Meaning |
|---|---|---|
| `gitops_deploy_key` | yes | SSH deploy key with write access to the gitops repo |

## Outputs

None. The step summary contains the link to open the gitops PR.

## How it works

Workflow settings: `permissions: {}` (the `GITHUB_TOKEN` gets nothing); `concurrency` group
`promote-<repository>-<app>` with `cancel-in-progress: false`. One job, `promote`, on
`[self-hosted, harbor-builder]`. Registry credentials are pre-stored on the host. Steps in order:

1. Validate inputs: `version` must be `X.Y.Z`; `project` and `app` must match `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`.
2. Copy: `skopeo inspect` on `<acc_registry>/<project>/<app>:<version>` (fail if missing), then `skopeo copy --all` to the prod registry.
   The Helm chart `<project>/charts/<app>:<version>` is inspected with `--raw` and copied the same way.
3. Stage the bump: write the deploy key and a pinned `github.com` host key to `/tmp`, clone `gitops_repo`, create the branch
   `promote/<app>-<version>`, set `.spec.sources[0].targetRevision` to the version with `yq` in the Application file
   (`gitops_app_file`, or `apps/prod/<app>.yaml`), commit as `promote(prod/<app>): <version>`, and push the branch.
   It fails if the file does not exist. The key files are removed on exit.
4. Summary: writes the compare URL for the branch (`.../compare/main...promote/<app>-<version>`) and a note that prod rolls out by itself
   if its Application auto-syncs.

## Example

```yaml
jobs:
  promote:
    uses: bizhostbv/actions/.github/workflows/k8s-promote.yml@v3
    with:
      project: myproject
      app: myapp
      version: 1.4.0
      gitops_repo: git@github.com:myorg/my-gitops.git
      gitops_app_file: apps/myapp/production.yaml
    secrets:
      gitops_deploy_key: ${{ secrets.GITOPS_DEPLOY_KEY }}
```
