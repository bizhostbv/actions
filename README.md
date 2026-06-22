# bizhostbv/actions

Reusable GitHub Actions workflows shared across the org. Public so any repo (any org/account) can call them.

## k8s-release — immutable container build+push pipeline

A `release/vX.Y.Z` branch builds one immutable image, pushes it to Harbor, and writes the image
tag directly into the GitOps repo (acc values file) so ArgoCD auto-syncs the acc environment.
Prod is promoted by a reviewed GitOps PR + manual sync. No moving tags, no cluster-side image
detection components.

Use it from any repo:

```yaml
# .github/workflows/release.yml
name: release
on:
  push: { branches: ['release/v*'] }
jobs:
  release:
    uses: bizhostbv/actions/.github/workflows/k8s-release.yml@v1
    with:
      project: myproject
      app: myapp
    secrets:
      gitops_deploy_key: ${{ secrets.GITOPS_DEPLOY_KEY }}
```

Full developer guide: [`docs/DEPLOYMENTS.md`](docs/DEPLOYMENTS.md). Pin `@v1` (a moving major tag).
