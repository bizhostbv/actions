# bizhostbv/actions

Reusable GitHub Actions workflows shared across the org. Public so any repo (any org/account) can call them.

## k8s-release — immutable container release pipeline

A `release/vX.Y.Z` branch builds one immutable image, pushes it to Harbor, and bumps the acc env in
GitOps (ArgoCD auto-syncs). Prod is promoted by a reviewed GitOps PR + manual sync. No moving tags.

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
