# Deploying your app on Kubernetes — Developer Guide

This is the standard way to ship any container app to our Kubernetes cluster. Follow it once
to onboard your app, then releasing is two commands.

## TL;DR

1. **A release is a branch.** `git switch -c release/v1.2.0 && git push -u origin release/v1.2.0`.
2. **That branch auto-deploys to acc** — CI builds and pushes `…:1.2.0`, then writes that tag
   into the GitOps repo; ArgoCD acc auto-syncs automatically.
3. **Prod is a small reviewed PR + one sync click.** Nothing reaches prod by accident.

Three rules that never bend:
- **Only immutable `:X.Y.Z` image tags.** No `:latest`, no `:acc`, no moving tags — ever. The
  version you see is exactly what is running, and rollback is "point at the previous number".
- **A version is built once and never reused.** Re-using `v1.2.0` is blocked by the registry and by CI.
- **One release pipeline runs at a time** (per app). A second release queues; it never collides.

---

## How it works (30-second mental model)

```
  you: push branch release/v1.2.0
        │
        ▼
  GitHub Actions (shared pipeline, runs on our build host)
    1. build image from your Dockerfile
    2. push  harbor.k8s-hotel.nl/<project>/<app>:1.2.0   (immutable)
    3. write "tag: 1.2.0" into gitops repo (values/acc/<app>.yaml)
        │
        ▼
  ArgoCD (acc)  ──auto-sync──►  your app runs in namespace <app>-acc
        │
   (you validate on acc)
        │
        ▼
  Promote: reviewed PR in gitops  +  ArgoCD "Sync" on prod
        │
        ▼
  ArgoCD (prod) ──manual-sync──►  your app runs in namespace <app>-prod
```

You never write pipeline YAML. The pipeline lives once, centrally, in the public `bizhostbv/actions`
repo. Your repo just calls it.

---

## Who does what

| Step | Who | When |
|------|-----|------|
| One-time platform setup (build runner, Harbor project, gitops apps, scoped deploy key) | **Platform/DevOps** | Once per app, see "Onboarding — platform" |
| Add the caller workflow + chart to the app repo | **You (developer)** | Once per app |
| Cut a release branch, release to acc | **You (developer)** | Every release |
| Approve the prod PR + click Sync | **A second maintainer** | Every prod promotion |

---

## Onboarding your app (developer part, ~10 minutes)

You need two things in your repo: a **release workflow** and a **Helm chart**. Both are copied
from templates — you only fill in your app name.

> Replace `myapp` (app name) and `myproject` (Harbor project — ask Platform which to use; often
> the same as the app) throughout.

### 1. Add the release workflow

When creating a new workflow in GitHub, pick the **"K8s immutable release"** template, or paste
this into `.github/workflows/release.yml`:

```yaml
name: release
on:
  push:
    branches: ['release/v*']
jobs:
  release:
    uses: bizhostbv/actions/.github/workflows/k8s-release.yml@v1
    with:
      project: myproject
      app: myapp
    secrets:
      gitops_deploy_key: ${{ secrets.GITOPS_DEPLOY_KEY }}
```

That is the entire CI config. The build/push/gitops-write logic is in the shared workflow — you
never copy or edit it.

> **GITOPS_DEPLOY_KEY secret:** Platform provides a scoped write deploy key to the GitOps repo.
> Add it to your app repo as a GitHub Actions secret named `GITOPS_DEPLOY_KEY`. This is a one-time
> step per repo — ask Platform/DevOps and they will generate and install it.

### 2. Make sure your app has a Dockerfile

The pipeline runs `docker build` on your repo's `Dockerfile` (root by default). If your image
builds locally, it builds in CI. Nothing special required.

```bash
docker build -t myapp:test .   # must succeed
```

### 3. Add the Helm chart

Copy `chart-template/` from `bizhostbv/actions` into your repo as `chart/`, then set your app
name in two places:

- `chart/Chart.yaml` → `name: myapp`
- `chart/values.yaml` → `image.repository` — leave the placeholder; the real registry is set
  **per environment** in the gitops `values/{acc,prod}/myapp.yaml` (acc and prod use different
  registries).

The chart is a minimal Deployment + Service. Add probes, env vars, or an Ingress as your app
needs — it is your chart from here on.

> **Registry is never hardcoded in CI.** The shared pipeline reads the registry from the
> `HARBOR_REGISTRY` GitHub Actions variable (set it at org/repo level, or pass the `registry`
> input). acc and prod set different values. The build pushes one immutable image; promoting to
> prod copies that exact image to the prod registry.

### 4. Tell Platform you're ready

Ask Platform/DevOps to do the one-time setup for `myapp` (Harbor project, the acc + prod
ArgoCD apps in the gitops repo, and the `GITOPS_DEPLOY_KEY` secret for your repo). They have a
checklist; you just need to give them: **app name**, **project name**, and **repo URL**.

Once Platform confirms, add the `GITOPS_DEPLOY_KEY` secret to your repo (Settings → Secrets →
Actions → New repository secret).

✅ **Onboarding done.** From now on, releasing is the next section.

---

## Releasing to acc (every release)

```bash
git switch main && git pull
git switch -c release/v1.2.0      # bump the version; never reuse a number
git push -u origin release/v1.2.0
```

That's it. Watch it:

- **Build/push + GitOps write:** GitHub → Actions tab → the "release" run. The pipeline builds
  the image, pushes `:1.2.0` to Harbor, then commits `image.tag: "1.2.0"` into
  `values/acc/myapp.yaml` in the gitops repo.
- **ArgoCD auto-sync:** ArgoCD UI at https://argocd.k8s-hotel.nl → app `myapp-acc` → detects
  the gitops change and auto-syncs → should go Synced/Healthy.
- **Image in registry:** https://harbor.k8s-hotel.nl → project `myproject` → `myapp` → tag `1.2.0`.

Now test your app on acc.

> **Why a branch and not just pushing to main?** Because the branch name *is* the version. It
> makes the release explicit, immutable, and traceable — and lets two releases queue safely.

---

## Promoting to prod (gated)

Prod runs the **exact same image** you validated on acc — never a fresh build.

1. Open a PR on the **gitops repo** (`bizhostbv/k8s-hotel-cluster-gitops`) that, for version `1.2.0`:
   - sets `apps/prod/myapp.yaml` → `targetRevision: release/v1.2.0`
   - sets `values/prod/myapp.yaml` → `image.tag: "1.2.0"`
2. **A second maintainer reviews and merges** the PR (four-eyes). *Note: on our current GitHub
   plan this review is a team agreement, not a hard technical block — treat it seriously.*
3. In ArgoCD, open `myapp-prod` and click **Sync**. This manual sync is the final gate; prod
   never deploys itself.

Done — `1.2.0` is in prod. acc is untouched (separate namespace, separate app, separate sync).

### Rolling back prod

Point prod back at the previous version: a PR setting `targetRevision`/`image.tag` to the last
good `X.Y.Z`, merge, Sync. Because every version is immutable and still in Harbor, rollback is
deterministic — no rebuild, no guessing.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| CI fails: *"version already exists — immutable"* | You reused a version number | Bump the semver and push a new `release/vX.Y.Z` branch |
| CI fails: *"Branch must be release/vMAJOR.MINOR.PATCH"* | Branch isn't named `release/vX.Y.Z` | Rename the branch to the exact pattern |
| CI fails: *"workflow was not found"* | Repo can't see the shared workflow | Platform must enable org access for `bizhostbv/.github` (one-time) |
| CI fails: *"Could not write tag to gitops after retries"* | GitOps repo push failed | Check `GITOPS_DEPLOY_KEY` secret is set and the deploy key has write access |
| Release run is "queued" | Another release for your app is still running | Expected — it runs next; releases never overlap |
| acc app `OutOfSync`/`Degraded` in ArgoCD | App/chart issue (bad probe, missing config) | Check pod logs; fix the chart; cut a new release |
| Prod won't update after merge | Prod is manual-sync by design | Click **Sync** on `myapp-prod` in ArgoCD |

---

## Reference

- **Shared pipeline (public):** `bizhostbv/actions/.github/workflows/k8s-release.yml` (pinned `@v1`)
- **Chart template (public):** `bizhostbv/actions` → `chart-template/`
- **"New workflow" UI template:** `bizhostbv/.github` → `workflow-templates/` (points at `bizhostbv/actions@v1`)
- **GitOps repo:** `bizhostbv/k8s-hotel-cluster-gitops` (acc/prod apps + values, promote runbook in `PROMOTE.md`)
- **Registry:** https://harbor.k8s-hotel.nl
- **ArgoCD:** https://argocd.k8s-hotel.nl

---

## Appendix — One-time platform setup (DevOps, per app)

Not for developers. Done once when onboarding `myapp`:

1. **Harbor:** create project `myproject`; add an immutable-tag rule matching `[0-9]*.[0-9]*.[0-9]*`.
2. **GitOps — acc:** add `apps/acc/myapp.yaml` (auto-sync, namespace `myapp-acc`) and
   `values/acc/myapp.yaml` (CI writes `image.tag` on each release).
3. **GitOps — prod:** add `apps/prod/myapp.yaml` (manual sync, tracks the release branch, namespace
   `myapp-prod`) and `values/prod/myapp.yaml` (pinned `image.tag`, bumped only by the promote PR).
4. **AppProject:** allow the app repo URL as an ArgoCD source.
5. **Runner:** confirm the self-hosted `harbor-builder` runner is available to the app repo.
6. **Scoped write deploy key + GITOPS_DEPLOY_KEY secret:** generate an SSH deploy key with write
   access scoped to the gitops repo. Install the public key as a deploy key on
   `bizhostbv/k8s-hotel-cluster-gitops` and add the private key as a GitHub Actions secret named
   `GITOPS_DEPLOY_KEY` on the app repo. This allows CI to commit the image tag directly into the
   gitops repo on each release.

Exact file contents and commands are maintained by the Platform team in the gitops repo and the
deployment implementation plan.
