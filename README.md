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

## Multi-arch (v3): every image for linux/amd64 and linux/arm64

From `@v3` the images are built natively on two runners and pushed as one manifest list, so they run
on the amd64 and the arm64 node pools alike. Both organisations (bizhostbv, globalcontrolgroup) have
runners with the same labels, so callers need nothing organisation-specific:

| Label | Runner |
|---|---|
| `[self-hosted, harbor-builder]` | amd64 buildah runner (`<org>-harbor-builder`) |
| `[self-hosted, harbor-builder-arm64]` | arm64 buildah runner (`<org>-harbor-builder-arm`) |

- `k8s-release-chart.yml@v3`: same inputs and secrets as v2; only the image is now multi-arch.
  Migrating is changing `@v1`/`@v2` into `@v3`.
- `build-multiarch.yml@v3`: just build + push one multi-arch image, for images without a chart
  (base images, tools). Registry defaults to `registry.k8s-bizhost.nl`; pass `registry:
  harbor.k8s-hotel.nl` for Harbor.

```yaml
jobs:
  image:
    uses: bizhostbv/actions/.github/workflows/build-multiarch.yml@v3
    with:
      image: gcg/node-base      # <project>/<name>
      tag: 22.4.0
    secrets:
      registry_username: ${{ secrets.REGISTRY_USERNAME }}   # optional: else the runner's own login
      registry_password: ${{ secrets.REGISTRY_PASSWORD }}
```

Next to `:X.Y.Z` the registry gets `:amd64-X.Y.Z` and `:arm64-X.Y.Z` (the per-arch halves; the arch
is a prefix so Harbor's immutable rule `[0-9]*.[0-9]*.[0-9]*` doesn't lock them before the manifest
list exists). Deploy `:X.Y.Z`.
