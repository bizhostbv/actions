{{- define "app.deployment" -}}
{{- include "app.scalingCheck" . -}}
{{- $a := .Values.autoscaling | default dict -}}
{{- $scaled := or (($a.hpa | default dict).enabled) (($a.keda | default dict).enabled) -}}
{{- $sel := include "app.componentSelector" (dict "root" . "component" "web") -}}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "app.fullname" . }}
  labels: {{- include "app.labels" . | nindent 4 }}
spec:
  {{- if not $scaled }}
  replicas: {{ .Values.replicas | default 1 }}
  {{- end }}
  selector:
    matchLabels: {{- $sel | nindent 6 }}
  {{- if (.Values.strategy | default dict).recreate }}
  strategy:
    type: Recreate
  {{- else }}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  {{- end }}
  template:
    metadata:
      labels: {{- include "app.labels" . | nindent 8 }}
        app.kubernetes.io/component: web
      {{- with .Values.podAnnotations }}
      annotations: {{- toYaml . | nindent 8 }}
      {{- end }}
    spec: {{- include "app.podSpec" (dict "root" . "s" .Values "what" "resources" "web" true) | nindent 6 }}
{{- end -}}
