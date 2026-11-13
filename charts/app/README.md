# app (library chart)

Renders the standard resources of an app. An app chart depends on it and has one template file:

```yaml
# Chart.yaml
dependencies:
  - name: app
    version: 1.0.0
    repository: oci://<registry>/base/charts   # or file://... for local work
```
```yaml
# templates/all.yaml
{{ include "app.all" . }}
```

## Example: PHP app (Symfony/Laravel)

FrankenPHP web, a queue worker on KEDA, CronJobs and a migrations Job, all from one image
(full file: `test/fixture/php-app.yaml`; nginx + php-fpm variant: `test/fixture/php-fpm.yaml`):

```yaml
image: { repository: harbor.example.com/app/shop, tag: "1.2.3" }
replicas: 2
envFrom: [{ secretRef: { name: shop } }]
metrics: { port: 2019 }
readinessProbe: { httpGet: { path: /healthz, port: http } }
resources: { requests: { cpu: 100m, memory: 256Mi } }
ingress: { enabled: true, hosts: [{ host: shop.example.com }] }
workers:
  messenger:
    command: [php, bin/console]
    args: [messenger:consume, async, --time-limit=3600]
    resources: { requests: { cpu: 100m, memory: 256Mi } }
    keda: { minReplicas: 1, maxReplicas: 6, triggers: [{ type: redis, metadata: { address: "shop-redis:6379", listName: messages, listLength: "50" } }] }
cronjobs:
  cleanup: { schedule: "0 3 * * *", command: [php, bin/console], args: [app:cleanup], resources: { requests: { cpu: 50m, memory: 128Mi } } }
migrations:
  enabled: true
  command: [php, bin/console]
  args: [doctrine:migrations:migrate, --no-interaction]
  resources: { requests: { cpu: 100m, memory: 256Mi } }
```

Redis and the database are not part of this chart: point `env`/`envFrom` at them.

## Example: Node app with nginx sidecar

`test/fixture/alert-manager.yaml`: `containerName: node`, `ports: [{name: node, containerPort: 3000}]`, a `sidecars`
nginx on `http` 8080, `service.port: 8080`, `ingress` on a sub-path, `metrics.port`.

Named templates: `app.all` renders everything below; the parts are `app.deployment`, `app.service`, `app.ingress`,
`app.hpa`, `app.scaledobject`, `app.pdb`, `app.vmservicescrape`, `app.serviceaccount`, `app.workers`, `app.cronjobs`,
`app.migrations`. Extras can reuse `app.fullname`, `app.labels`, `app.podSpec`.

Test: `charts/app/test/run.sh` (needs `helm` and `yq`; runs `kubeconform` when installed).

## Values

`*` = required, rendering fails without it.

| Key | Default | Meaning |
|---|---|---|
| `fullnameOverride` | release name | Name of every resource |
| `image.repository` * / `image.tag` * | | Tag may be `1.2.3@sha256:...`. Empty tag fails |
| `image.pullPolicy` | `IfNotPresent` | |
| `imagePullSecrets` | `[{name: harbor-pull}]` | |
| `replicas` | `1` | Ignored when HPA or KEDA is on |
| `strategy.recreate` | `false` | Only way to get `Recreate`; default is RollingUpdate `maxUnavailable: 0`, `maxSurge: 1` |
| `containerName` | `app` | Name of the main container |
| `command`, `args`, `env`, `envFrom` | | Main container, verbatim |
| `ports` | `[{name: http, containerPort: 8080}]` | Main container ports. `metrics.port` is appended as `metrics` |
| `readinessProbe` * | | Main container |
| `livenessProbe`, `startupProbe`, `lifecycle` | | Main container, optional |
| `resources.requests` * | | `limits.memory` defaults to `requests.memory`. No CPU limit is ever set by default |
| `readOnlyRootFilesystem` | `false` | Not `true` by default: Node, PHP and nginx write temp/cache files and break at start. Set `true` plus `volumes`/`volumeMounts` for `emptyDir` paths where the app allows it |
| `podSecurityContext` | `runAsNonRoot`, uid/gid/fsGroup 1000 | Replaces the whole default |
| `volumes`, `volumeMounts` | | Verbatim |
| `sidecars` | | List of containers, rendered verbatim after the main one |
| `podAnnotations`, `nodeSelector`, `tolerations`, `affinity` | | Passthrough |
| `extraPodSpec` | | Map merged into the pod spec (`terminationGracePeriodSeconds`, `initContainers`, ...) |
| `serviceAccount.create` / `.name` | `true` / fullname | |
| `service.port` / `service.targetPort` | `80` / `http` | Service port is named `http`; `targetPort` may be a name or number. Gets a `metrics` port when `metrics.port` is set |
| `ingress.enabled` | `false` | |
| `ingress.hosts` * | | `[{host, paths: [{path, pathType}]}]`; paths default to `/`, pathType to `Prefix` |
| `ingress.className` | `haproxy` | |
| `ingress.clusterIssuer` | `lets-encrypt-cloudflare` | `""` drops the annotation (certificate owned by another Ingress) |
| `ingress.tls.secretName` | `<fullname>-tls` | |
| `ingress.allowList` | | CIDR list, comma-joined into `haproxy.org/allow-list`. Values only, nothing built in |
| `ingress.annotations` | | Extra annotations |
| `ingress.monitoring` | `true` | `false` adds label `blackbox-exporter/ignore: "true"`; only for a first rollout |
| `autoscaling.hpa.enabled` / `minReplicas` / `maxReplicas` * / `cpu` | off / 1 / / 70 | |
| `autoscaling.keda.enabled` / `minReplicas` / `maxReplicas` * / `triggers` * | off / 1 / / | Triggers verbatim. HPA and KEDA together fails |
| `metrics.port` | | Enables the `metrics` container and Service port plus a VMServiceScrape |
| `metrics.path` / `metrics.enabled` | `/metrics` / `true` | `enabled: false` turns the scrape off |

### workers, cronjobs, migrations

All three reuse the web image, `env`, `envFrom`, `volumes`, `podSecurityContext`, pull secrets and container hardening.
`resources.requests` is required on each (rendering fails without it). None of them sets `ttlSecondsAfterFinished`.

| Key | Meaning |
|---|---|
| `workers.<name>` | Deployment `<fullname>-worker-<name>`, no Service, Ingress or readinessProbe. `command`, `args`, `livenessProbe`, `terminationGracePeriodSeconds` (60), `replicas` (1) |
| `workers.<name>.keda` / `.hpa` | `{minReplicas (1), maxReplicas *, triggers *}` / `{minReplicas, maxReplicas *, cpu (70)}`. Both on one worker fails. PDB when the minimum is 2 or more |
| `cronjobs.<name>` | CronJob `<fullname>-cron-<name>`. `schedule` *, `command`, `args`, `concurrencyPolicy` (Forbid), `successfulJobsHistoryLimit` (3), `failedJobsHistoryLimit` (1), `startingDeadlineSeconds` (300), `backoffLimit` (0), `activeDeadlineSeconds`. Old Jobs are cleaned by the history limits |
| `migrations` | `enabled` or `command` turns on Job `<fullname>-migrations`: ArgoCD `Sync` hook at sync-wave -1 (ServiceAccount at -2, Deployments at 0), `BeforeHookCreation`, `backoffLimit: 0`, `activeDeadlineSeconds` (600) |

Migrations must be backwards compatible (expand/contract): the hook runs the new schema while the old pods still serve. Put the app's SopsSecret at sync-wave -2 or earlier so the Job finds its env on a first install.
No TTL on the hook Job: a TTL-deleted hook Job would show up as out of sync; `BeforeHookCreation` removes the previous one.

Pods carry `app.kubernetes.io/component` (`web`, `worker-<name>`, ...), so the web Service and PDB select web pods only.

The PDB (`minAvailable: 1`) renders when the effective minimum replicas (replicas, HPA min or KEDA min) is 2 or more.

Labels: `app.kubernetes.io/{name,instance,version,managed-by}`; name is the chart name, version is the app chart's
`appVersion`.
