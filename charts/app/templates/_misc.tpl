{{- define "app.vmservicescrape" -}}
{{- $m := .Values.metrics | default dict -}}
{{- if and $m.port (ne (toString $m.enabled) "false") -}}
---
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMServiceScrape
metadata:
  name: {{ include "app.fullname" . }}
  labels: {{- include "app.labels" . | nindent 4 }}
spec:
  selector:
    matchLabels: {{- include "app.selectorLabels" . | nindent 6 }}
  endpoints:
    - port: metrics
      path: {{ $m.path | default "/metrics" }}
{{- end -}}
{{- end -}}

{{- define "app.serviceaccount" -}}
{{- if ne (toString (.Values.serviceAccount | default dict).create) "false" -}}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "app.serviceAccountName" . }}
  labels: {{- include "app.labels" . | nindent 4 }}
  annotations:
    argocd.argoproj.io/sync-wave: "-2"
{{- end -}}
{{- end -}}
