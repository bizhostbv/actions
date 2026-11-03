{{- define "app.fullname" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "app.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "app.labels" -}}
{{ include "app.selectorLabels" . }}
{{- with .Chart.AppVersion }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "app.serviceAccountName" -}}
{{- (.Values.serviceAccount | default dict).name | default (include "app.fullname" .) -}}
{{- end -}}

{{/* Fails when HPA and KEDA are both on: they would fight over the same Deployment. */}}
{{- define "app.scalingCheck" -}}
{{- $a := .Values.autoscaling | default dict -}}
{{- if and (($a.hpa | default dict).enabled) (($a.keda | default dict).enabled) -}}
{{- fail "autoscaling.hpa.enabled and autoscaling.keda.enabled are both true: pick one (never both on one Deployment)" -}}
{{- end -}}
{{- end -}}

{{/* Minimum replica count that applies, as a string. Used for the PDB and the replicas field. */}}
{{- define "app.minReplicas" -}}
{{- $a := .Values.autoscaling | default dict -}}
{{- $hpa := $a.hpa | default dict -}}
{{- $keda := $a.keda | default dict -}}
{{- if $hpa.enabled -}}{{ $hpa.minReplicas | default 1 }}
{{- else if $keda.enabled -}}{{ $keda.minReplicas | default 1 }}
{{- else -}}{{ .Values.replicas | default 1 }}
{{- end -}}
{{- end -}}

{{- define "app.all" -}}
{{ include "app.serviceaccount" . }}
{{ include "app.deployment" . }}
{{ include "app.service" . }}
{{ include "app.ingress" . }}
{{ include "app.hpa" . }}
{{ include "app.scaledobject" . }}
{{ include "app.pdb" . }}
{{ include "app.vmservicescrape" . }}
{{ include "app.workers" . }}
{{ include "app.cronjobs" . }}
{{ include "app.migrations" . }}
{{- end -}}
