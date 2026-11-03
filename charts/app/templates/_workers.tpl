{{/* One Deployment (+ ScaledObject or HPA, + PDB) per entry of .Values.workers. */}}
{{- define "app.workers" -}}
{{- $root := . -}}
{{- range $n, $w := .Values.workers }}
{{- $name := printf "%s-worker-%s" (include "app.fullname" $root) $n -}}
{{- $what := printf "workers.%s.resources" $n -}}
{{- if and $w.keda $w.hpa -}}{{- fail (printf "workers.%s: keda and hpa are both set: pick one (never both on one Deployment)" $n) -}}{{- end -}}
{{- $sel := include "app.componentSelector" (dict "root" $root "component" (printf "worker-%s" $n)) -}}
{{- $min := int ($w.keda | default $w.hpa | default (dict "minReplicas" ($w.replicas | default 1))).minReplicas | default 1 -}}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $name }}
  labels: {{- include "app.labels" $root | nindent 4 }}
spec:
  {{- if not (or $w.keda $w.hpa) }}
  replicas: {{ $w.replicas | default 1 }}
  {{- end }}
  selector:
    matchLabels: {{- $sel | nindent 6 }}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  template:
    metadata:
      labels: {{- include "app.labels" $root | nindent 8 }}
        app.kubernetes.io/component: worker-{{ $n }}
      {{- with $root.Values.podAnnotations }}
      annotations: {{- toYaml . | nindent 8 }}
      {{- end }}
    spec: {{- include "app.podSpec" (dict "root" $root "s" $w "what" $what "grace" ($w.terminationGracePeriodSeconds | default 60)) | nindent 6 }}
{{- if $w.keda }}
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: {{ $name }}
  labels: {{- include "app.labels" $root | nindent 4 }}
spec:
  scaleTargetRef:
    name: {{ $name }}
  minReplicaCount: {{ $w.keda.minReplicas | default 1 }}
  maxReplicaCount: {{ required (printf "workers.%s.keda.maxReplicas is required" $n) $w.keda.maxReplicas }}
  triggers: {{- toYaml (required (printf "workers.%s.keda.triggers is required" $n) $w.keda.triggers) | nindent 4 }}
{{- end }}
{{- if $w.hpa }}
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ $name }}
  labels: {{- include "app.labels" $root | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ $name }}
  minReplicas: {{ $w.hpa.minReplicas | default 1 }}
  maxReplicas: {{ required (printf "workers.%s.hpa.maxReplicas is required" $n) $w.hpa.maxReplicas }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ $w.hpa.cpu | default 70 }}
{{- end }}
{{- if ge $min 2 }}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ $name }}
  labels: {{- include "app.labels" $root | nindent 4 }}
spec:
  minAvailable: 1
  selector:
    matchLabels: {{- $sel | nindent 6 }}
{{- end }}
{{- end }}
{{- end -}}
