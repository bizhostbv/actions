{{- define "app.hpa" -}}
{{- include "app.scalingCheck" . -}}
{{- $h := ((.Values.autoscaling | default dict).hpa | default dict) -}}
{{- if $h.enabled -}}
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "app.fullname" . }}
  labels: {{- include "app.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "app.fullname" . }}
  minReplicas: {{ $h.minReplicas | default 1 }}
  maxReplicas: {{ required "autoscaling.hpa.maxReplicas is required" $h.maxReplicas }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ $h.cpu | default 70 }}
{{- end -}}
{{- end -}}

{{- define "app.scaledobject" -}}
{{- include "app.scalingCheck" . -}}
{{- $k := ((.Values.autoscaling | default dict).keda | default dict) -}}
{{- if $k.enabled -}}
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: {{ include "app.fullname" . }}
  labels: {{- include "app.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    name: {{ include "app.fullname" . }}
  minReplicaCount: {{ $k.minReplicas | default 1 }}
  maxReplicaCount: {{ required "autoscaling.keda.maxReplicas is required" $k.maxReplicas }}
  triggers: {{- toYaml (required "autoscaling.keda.triggers is required" $k.triggers) | nindent 4 }}
{{- end -}}
{{- end -}}

{{- define "app.pdb" -}}
{{- if ge (int (include "app.minReplicas" .)) 2 -}}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "app.fullname" . }}
  labels: {{- include "app.labels" . | nindent 4 }}
spec:
  minAvailable: 1
  selector:
    matchLabels: {{- include "app.componentSelector" (dict "root" . "component" "web") | nindent 6 }}
{{- end -}}
{{- end -}}
