# Deploy standard for the gwsn cluster

Status: approved by the lead on 3 Nov 2026. The shared pipeline (§8) is being built. Until it ships, the existing
workflows and [`DEPLOYMENTS.md`](DEPLOYMENTS.md) keep working; this document then replaces `DEPLOYMENTS.md`.
This repo is public, so this document names no IP addresses, secrets or customer internals.

**Scope.** This is the baseline for every application on the `gwsn-production` cluster: Bizhost-internal apps,
customer projects and GCG, as they move there.

**The typical application** is a standard PHP application (Symfony or Laravel type) with:
- a web Deployment, either FrankenPHP or nginx + php-fpm;
- queue workers;
- CronJobs;
- a migrations Job;
- Redis;
- an external database.

Everything in this document is written for that case first. Node services fit the same flow. Applications that ship
binaries to devices use the optional [Appendix A](#appendix-a-edge-binaries-optional).

Lead, 3 Nov 2026:
- "dit geld dus voor voor alle projecten die op gwsn cluster draaien dat dit de basis wordt";
- "de deployflow wil ik voor alle applicaties zo goed als hetzelfde hebben".

Not in scope: CI for repos that ship no service on the cluster (libraries, the design system).

## 1. Flow

Lead, 3 Nov 2026:
- "dus we gaan alleen main gebruiken, main wordt altijd beschermd als dat kan en mag je alleen naar toe merge vanuit een
  merge request. na de merge komt er een pipeline die automatisch een versie tagged en deze uitrolt naar acceptatie
  omgeving (push naar gitops) en een manual handeling die klaarstaat om de productie te release (dat is dus ook een
  commit in gitops op de productie)".
- "versie taggen is dus image bouwen en taggen en pushen naar harbor en daarna naar gitops een commit".

**Branches.** `main` only, plus short-lived PR branches. `main` is protected wherever the platform allows. The only way
in is a merged PR.

**The pipeline after a merge to `main`, in this order:**
1. Compute `X.Y.Z` and create the git tag.
2. Build the image and tag it `X.Y.Z`; package the chart as `X.Y.Z`.
3. Push the image and chart to harbor.
4. Commit the acc bump (`X.Y.Z`) to the gitops repo. ArgoCD syncs acc.
5. Manual job "Release to production" (guards in 1.1): commits the same `X.Y.Z` to gitops prod. ArgoCD syncs prod.

Each step runs only if the previous one succeeded. A version that is not in harbor never reaches gitops.

Rules that apply to every step:
- **Prod is always manual (hard rule).** Nothing reaches production without a member of `release-admins` running the
  production job. That includes Renovate updates and security fixes. There is no exception path and no automerge to
  prod. Lead, 3 Nov 2026: "de merge op productie blijft altijd handmatig ook voor renovate".
- **Version format.** Computed from the conventional-commit PR title: `feat` gives a minor bump, `fix` a patch bump,
  `!` a major bump. PRs are squash-merged and a check enforces the title.
  - The git tag, the image tag and the chart version are all the same `X.Y.Z`, with no `v` prefix.
  - Never a pipeline ID, never `latest`, never a branch name.
- **Build once.** acc and prod run the same image. Prod only gets a version acc already ran.
- **No cluster access from CI.** CI writes to harbor and to gitops. It never talks to a cluster: no helm or kubectl
  deploy jobs.
- **Migrations are backwards compatible** (expand/contract), so the previous release still runs on the new schema.
  Without that, a rollback is not safe.
- **Changelog.** The release notes are generated from the commits.
- **Implementation.** One shared implementation, with a thin wrapper for GitHub and one for GitLab (§8).

### 1.1 The production job

| Guard | How |
|---|---|
| Who | Only members of the group `release-admins` (§9). The job checks the person who started it, as its first step, against that group in the GitHub org or GitLab group. The job only runs on `main`. |
| Same tag as acc | The version is not typed in. The job reads it from the gitops `acceptance.yaml` and checks that the image exists in harbor. |
| No going backwards | The job refuses a version equal to or older than the one in `production.yaml`. |
| Rollback | The same job with `rollback: X.Y.Z`. It only accepts a version that `production.yaml` held before, according to the git history. |
| Concurrency | One concurrency group per app. The gitops push rebases and retries. |
| Audit | Commit message `release(<app>): X.Y.Z to production by <actor>`, plus a link to the run. The git history of `production.yaml` is the release log. |


## 2. Tenancy: what every customer or product gets

Every customer gets the same set of resources. A product inside a customer only gets its own set when its access has to
differ.

| Thing | Name | Example (GCG) |
|---|---|---|
| Harbor project (images, `charts/`, edge artifacts) | `<customer>` | `gcg` (Connect included) |
| Harbor robots | `<customer>-push` (CI), `<customer>-pull` (cluster) | `gcg-push`, `gcg-pull` |
| Namespaces | `<customer>[-<product>]-<env>`, env `acc` or `prod` | `gcg-acc`, `gcg-connect-prod` |
| Pull secret in every namespace | SopsSecret `harbor-pull` (from `<customer>-pull`) | |
| Gitops repo | one per customer, `<customer>-gitops`, in the customer's GitHub org or GitLab group | `gcg-gitops-repo` (existing name stays) |
| ArgoCD AppProject | `<customer>`: sources = its gitops repo + `registry.k8s-bizhost.nl/<customer>`; destinations = `<customer>-*` namespaces on gwsn | `gcg` |
| Parent Application | one per customer in `support-kubernetes-infra`, globbing `gwsn/*/argocd/*.yaml` in that customer's gitops repo | one MR when a customer is onboarded, never per app |
| CI → gitops write | GitHub: the org's `deployflow` GitHub App (contents write on the gitops repo, members read for the group check). GitLab: a project access token on the gitops project. | |
| Access groups | `release-admins`, `devops`, `developers` (§9) in the customer's GitHub org or GitLab group | |

Onboarding a customer is one change, by Bizhost: one MR in `support-kubernetes-infra` that creates the harbor project,
the robots, the AppProject and the parent Application. After that, adding an app needs no infra change.

## 3. Gitops layout (every customer gitops repo)

```
gwsn/<app>/argocd/{acceptance,production}.yaml      # Application, chart from harbor OCI, targetRevision X.Y.Z
gwsn/<app>/environments/<env>/values.yaml
gwsn/<app>/environments/<env>/manifests/            # SopsSecret and other plain manifests
```

- **Chart.** Comes from `registry.k8s-bizhost.nl/<customer>/charts/<app>:X.Y.Z`. Never vendored in gitops.
- **Application block.** Identical everywhere:
  - automated `prune` + `selfHeal` on acc and prod;
  - `syncOptions: [CreateNamespace=true, PruneLast=true, ServerSideApply=true]`;
  - retry 5×, starting at 30 s.
  - The manual production job is the gate; nobody clicks Sync.
- **Jobs.**
  - Migrations run as an ArgoCD `Sync` hook at sync-wave -1 with `BeforeHookCreation`; the app's SopsSecret sits at
    sync-wave -2 or earlier.
  - No `ttlSecondsAfterFinished` on anything ArgoCD owns (selfHeal would recreate it).
  - CronJobs keep their history through history limits.
- **Secrets.** SopsSecret, never inside a chart. ESO/Azure Key Vault only for what Bizhost manages (database
  credentials).

## 4. Images

- **One base-image source for the whole cluster.** The `base-images` repo (today
  `globalcontrolgroup/base-images`) moves to `bizhostbv/base-images` and pushes to harbor project `base`:
  - `php-base` (FrankenPHP)
  - `node-base`
  - `nginx-base` (new)

  All are Debian slim, built for amd64 and arm64, rebuilt weekly behind a Trivy gate. `bizhost/devops/base-images`
  (GitLab) is retired.
- **Pinning.** Services pin `tag@sha256:digest`.
- **User.** Runtime images run as uid 1000.
- **Tags.** `X.Y.Z` is immutable in harbor. Non-release artifacts are deleted after 30 days.

### 4.1 Dependencies: Renovate with a cooldown

Lead, 3 Nov 2026: "niet alleen base images maar ook node modules en composer. wel met een cooldown, we willen niet een
geinfecteerde package dezelfde dag nog geinstalleerd is op ons cluster. een renovate mag na alle testen op groen
automatisch gemerged worden op main."

- **Coverage.** Every app repo extends the shared Renovate preset, which moves to a Bizhost-owned public repo so that
  GitHub and GitLab repos use the same one. Renovate covers base images, npm, composer, the shared workflow or template
  pin, and the `app` chart dependency.
- **Cooldown.** Every update waits `minimumReleaseAge` before Renovate offers it, so no package reaches the cluster on
  the day it was published.

  | Update | Cooldown | Automerge after green checks |
  |---|---|---|
  | patch, minor, digest (npm, composer, docker, actions) | 3 days | yes |
  | own base images (`base/*`, already filtered upstream) | none | yes |
  | security fix (vulnerability alert) | 1 day | yes |
  | major | 3 days | no, a person merges (recommended; the lead may choose automerge for majors too) |

- **Security fixes wait 1 day.** The trade-off: a known vulnerability stays open on the cluster for up to a day longer.
  In exchange, a hijacked "security" release, a common attack pattern, does not reach the cluster on its release day.
  For a vulnerability that is being actively exploited, a person can merge the Renovate PR to `main` before the day is
  over. Prod still goes through the manual production job.
- **PR titles.** Renovate uses conventional titles (`semanticCommits`). Runtime dependencies and images get
  `fix(deps): …`, which releases as a patch and reaches acc. Dev dependencies and CI actions get `chore(deps): …`, which
  releases nothing, because they do not change what runs.
- **Automerge stops at acc.** A Renovate PR that is green merges by itself, and that merge releases to acc like any
  other. Prod is always the manual production job (§1), also for Renovate and security fixes.
- **Limit.** The cooldown covers the dependency Renovate bumps and its lockfile changes. It does not check the age of
  every transitive package that a fresh lockfile resolves. Lockfile maintenance therefore stays manual (no automerge),
  and the app's CI runs `npm audit` / `composer audit` plus the image scan.

## 5. Chart

**Shared library chart: `app`.** It lives in `bizhostbv/actions/charts/app` (successor of `chart-template`) and is
published to harbor `base/charts/app`. Every app chart lives in its app repo and depends on it.

The library chart renders the standard resources:
- Deployment
- Service
- Ingress
- HPA or KEDA ScaledObject
- PDB
- VMServiceScrape
- ServiceAccount

For the typical PHP application, the same chart also renders, from the same image:
- **workers:** one Deployment per worker, KEDA on queue depth;
- **cronjobs:** one CronJob each, with `concurrencyPolicy: Forbid` and history limits;
- **migrations:** a Job run as an ArgoCD `Sync` hook at sync-wave -1, after the ServiceAccount and secrets and before
  the Deployments, with `BeforeHookCreation`, `backoffLimit: 0` and no TTL.

Apps only add templates for what really is their own.

```yaml
# values for a typical PHP application
image: { repository: registry.k8s-bizhost.nl/<customer>/<app> }   # tag is set by the pipeline
ports: [{ name: http, containerPort: 8080 }]
metrics: { port: 2019 }
readinessProbe: { httpGet: { path: /readyz, port: http } }
livenessProbe:  { httpGet: { path: /healthz, port: http } }
resources: { requests: { cpu: 100m, memory: 256Mi } }
envFrom: [{ secretRef: { name: <app>-env } }]
autoscaling: { hpa: { enabled: true, minReplicas: 2, maxReplicas: 6 } }
ingress: { hosts: [{ host: <app>.example.org, paths: [{ path: / }] }] }
workers:
  messenger:
    command: [php, bin/console, messenger:consume, async, --time-limit=3600]
    resources: { requests: { cpu: 50m, memory: 192Mi } }
    keda: { minReplicaCount: 1, maxReplicaCount: 10, triggers: [ ... ] }
cronjobs:
  cleanup: { schedule: "15 3 * * *", command: [php, bin/console, app:cleanup], resources: { requests: { cpu: 50m, memory: 128Mi } } }
migrations:
  command: [php, bin/console, doctrine:migrations:migrate, --no-interaction]
  resources: { requests: { cpu: 100m, memory: 256Mi } }
```

Defaults that make the platform rules the easy path:
- **Rollout.** `RollingUpdate`, `maxUnavailable: 0`, `maxSurge: 1`.
- **Probes.** A `readinessProbe` is required; the chart does not render without one.
- **Resources.** `resources.requests` is required. The memory limit equals the memory request; there is no CPU limit.
- **Security.** `runAsNonRoot: true`; a read-only root filesystem where possible.
- **Ingress.**
  - Class `haproxy`, issuer `lets-encrypt-cloudflare`.
  - On acc, an IP allow-list from one shared list.
  - `ingress.monitoring: false` renders `blackbox-exporter/ignore: "true"`. It is only for a first rollout.
- **Availability.** Prod runs at least 2 replicas, with a PDB of `minAvailable: 1`.
- **Scaling.** Web workloads scale with HPA on CPU (70 %); workers scale with KEDA on queue depth. Never both on one
  Deployment.

## 6. Endpoints and monitoring

- **Endpoints.**
  - `/healthz`: liveness, with no dependencies.
  - `/readyz`: readiness, covering the service's own dependencies.
  - `/metrics`: Prometheus format, on its own port, never routed through the Ingress.
- **No P1 from a release (platform monitoring).** Every Ingress host and path is probed every minute. A failed probe
  pages on-call as a P1.
  - Every Ingress path returns 2xx on its root without authentication.
  - After every acc sync, a check requests each Ingress path.
  - A new Ingress either has a Ready pod in the same PR, or ships with `ingress.monitoring: false`, removed once the path
    returns 2xx.
- **Scraping.** VMServiceScrape is on by default.
- **Standard alerts (VMRule).** Restarts; not Ready for more than 5 minutes; 5xx rate; queue depth. There is one
  dashboard per runtime.

## 7. Source hosting

- **GitHub** (`bizhostbv`, `globalcontrolgroup`, or the customer's own org) and **GitLab** (`bizhost`, `gwsn`) are both
  supported with the same pipeline (§8). GCG moves to GitHub (lead, 3 Nov 2026); other projects choose.
- **Protecting `main`.** A GitHub org with private application repos needs GitHub Team, because Free cannot protect
  branches on private repos. GitLab Free can protect branches.

## 8. Shared pipeline: one implementation, two wrappers

Lead, 3 Nov 2026: "dan kunnen we dus ook een shared pipeline actions voor github en in gitlab, houd er rekening mee dat
het niet meer alleen gcg is maar ook gwsn en bizhost".

| Part | Where | What |
|---|---|---|
| Implementation | `bizhostbv/actions/deployflow/` | Shell scripts for each step: `version`, `build`, `push`, `gitops-acc`, `release-prod`. They take every project value as input. Nothing customer-specific is built in. |
| Tool image | `registry.k8s-bizhost.nl/base/deployflow:X.Y.Z` | The scripts plus buildah, skopeo, helm, oras, yq and git. Built from the same repo with this same pipeline. |
| GitHub wrapper | `bizhostbv/actions/.github/workflows/deploy.yml` | A reusable workflow. Each job calls a script. |
| GitLab wrapper | `bizhostbv/actions/gitlab/deploy.yml` | A CI template with `spec:inputs`, included with `include: remote` from the public repo at a release tag, so no GitLab project is needed. Each job runs in the tool image and calls the same script. |

Both wrappers are versioned with the same `X.Y.Z` as the scripts, and a repo pins one version. The values each project
passes:
- harbor project;
- app name;
- Dockerfile, build context and chart directory;
- gitops repo and the paths of its acc and prod Application files;
- the GitHub org or GitLab group that holds the access groups.

Builds run on native amd64 and arm64 runners, labelled `harbor-builder` and `harbor-builder-arm64` on both platforms.

## 9. Access groups

Three groups, with the same names everywhere: `release-admins`, `devops`, `developers`. Lead, 3 Nov 2026: "heel simpel
we hebben 3 groepen, release-admins, devops en developers".

| | developers | devops | release-admins |
|---|---|---|---|
| App repo | Open a PR/MR and review. Merge to `main` after one approval and green checks. | As developers. Also owns CI, chart and Dockerfile (CODEOWNERS approval on those paths). | As developers. |
| Production job | No | No | Yes, the only group allowed. That includes rollback. |
| Gitops repo | Open a PR. | Approve and merge gitops PRs (CODEOWNERS). | Approve and merge gitops PRs. |
| Harbor | Read: pull, view scans. | Read, plus manage retention and scans for the project. | Read. |
| ArgoCD | Read: status, diff, logs. | Read, plus refresh. | Read. |

Rules that apply to all groups:
- **Gitops writes.** Only CI commits directly to gitops `main` (acc and prod bumps). Humans change gitops only through a
  PR/MR.
- **Nobody syncs, rolls back or deletes in the ArgoCD UI.** A rollback is the production job.

**Per-customer scoping, with no new group names.**
- On GitHub, each org has its own three teams.
- On GitLab, each top-level group (`bizhost`, `gwsn`) has the three groups as subgroups. A project or customer subgroup
  is shared with them at the matching role.
- Harbor and ArgoCD map the same groups through SSO group claims (`<org>:<group>`). The ArgoCD AppProject of a customer
  only grants that customer's groups.
- Owners of the orgs and groups (Bizhost) sit outside this matrix.

## Appendix A. Edge binaries (optional)

This appendix applies only to applications that ship binaries to devices, such as the Connect connector. Standard
applications skip it.

- **Same pipeline.** Steps 1–3 run as for any service, but the artifact is signed binaries, pushed to harbor as an OCI
  artifact (oras).
- **Step 4** commits the version to acc.
- **Step 5** is the production job. It marks `X.Y.Z` as `stable` in the application's release source, and devices only
  install `stable`.
