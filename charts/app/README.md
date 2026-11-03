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

Named templates: `app.deployment`, `app.service`, `app.ingress`, `app.hpa`, `app.scaledobject`, `app.pdb`,
`app.vmservicescrape`, `app.serviceaccount`, and `app.all` (all of them). An app that needs more (workers, migrations,
CronJobs) adds its own templates beside it and can reuse `app.fullname`, `app.labels`, `app.selectorLabels`.

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

The PDB (`minAvailable: 1`) renders when the effective minimum replicas (replicas, HPA min or KEDA min) is 2 or more.

Labels: `app.kubernetes.io/{name,instance,version,managed-by}`; name is the chart name, version is the app chart's
`appVersion`.
