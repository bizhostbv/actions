# actions

Shared, reusable CI/CD workflows and Helm charts.

| Action | What it does | Docs |
|---|---|---|
| `build-multiarch.yml` | Builds one image for amd64 and arm64 and pushes it as a single multi-arch tag. | [docs/build-multiarch.md](docs/build-multiarch.md) |
| `ci-checks.yml` | Lint, test and SAST gate for Node and PHP apps. | [docs/ci-checks.md](docs/ci-checks.md) |
| `k8s-promote.yml` | Copies an acc image and chart to the prod registry and stages the prod bump in the gitops repo. | [docs/k8s-promote.md](docs/k8s-promote.md) |
| `k8s-release.yml` | Builds an immutable multi-arch image from a `release/vX.Y.Z` branch and writes the tag into the gitops values for acc. | [docs/k8s-release.md](docs/k8s-release.md) |
| `k8s-release-chart.yml` | Builds an immutable multi-arch image and Helm chart and bumps the acc Application in the gitops repo. | [docs/k8s-release-chart.md](docs/k8s-release-chart.md) |
| `deploy.yml` | deployflow: version, build, publish and acceptance bump on a push to the default branch. | [deployflow/README.md](deployflow/README.md#deployyml) |
| `release-production.yml` | deployflow: guarded production release or rollback, by a member of `release-admins`. | [deployflow/README.md](deployflow/README.md#release-productionyml) |
| `pr-title.yml` | deployflow: fails a pull request whose title is not a conventional commit. | [deployflow/README.md](deployflow/README.md#pr-titleyml) |
| `gitlab/deploy.yml` | deployflow for GitLab: the same pipeline as a GitLab CI template. | [deployflow/README.md](deployflow/README.md#gitlabdeployyml) |
| `charts/app` | Library Helm chart that renders the standard resources of an app. | [charts/app/README.md](charts/app/README.md) |
| `chart-template` | Starter Helm chart for a new app. | [chart-template/README.md](chart-template/README.md) |
