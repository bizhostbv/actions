# chart-template

A minimal starter Helm chart for a new app. It is a plain `application` chart (not the library chart in [`charts/app`](../charts/app/README.md)).
Copy it, replace the placeholders, and extend it.

## What is in it

| File | Content |
|---|---|
| `Chart.yaml` | `name: APPNAME`, `type: application`, `version` and `appVersion` `0.1.0` |
| `values.yaml` | `image.repository` (`REGISTRY/PROJECTNAME/APPNAME`), `image.tag` (`0.0.0`), `image.pullPolicy`, `replicaCount` (1), `service.port` (80), `service.targetPort` (8080), `resources` (requests 50m CPU and 64Mi memory; limits 500m CPU and 256Mi memory) |
| `templates/deployment.yaml` | A Deployment named after the chart, one container, image from `image.repository` and `image.tag`, container port `service.targetPort`, `resources` |
| `templates/service.yaml` | A Service named after the chart, port `service.port` to `service.targetPort` |

It has no Ingress, probes, autoscaling or other resources. Add what the app needs.

## How to use it

1. Copy the directory into the app repo as `chart/` (the default `chart_dir` of the release workflows).
2. Replace `APPNAME` in `Chart.yaml` with the app name. The chart name must equal the `app` input of the release workflow.
3. In `values.yaml`, replace `REGISTRY/PROJECTNAME/APPNAME` with the real image repository. The registry differs per environment, so the
   full repository is normally set in the gitops values per environment; the value here is only a placeholder.
4. Leave `image.tag` alone. The release workflows set it to the released version when they package the chart
   (see [k8s-release-chart](../docs/k8s-release-chart.md) and [deployflow](../deployflow/README.md)).
5. Check it renders: `helm lint chart` and `helm template chart`.
