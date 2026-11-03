{{/* One CronJob per entry of .Values.cronjobs. No ttlSecondsAfterFinished: the history limits clean up. */}}
{{- define "app.cronjobs" -}}
{{- $root := . -}}
{{- range $n, $c := .Values.cronjobs }}
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ include "app.fullname" $root }}-cron-{{ $n }}
  labels: {{- include "app.labels" $root | nindent 4 }}
spec:
  schedule: {{ required (printf "cronjobs.%s.schedule is required" $n) $c.schedule | quote }}
  concurrencyPolicy: {{ $c.concurrencyPolicy | default "Forbid" }}
  successfulJobsHistoryLimit: {{ $c.successfulJobsHistoryLimit | default 3 }}
  failedJobsHistoryLimit: {{ $c.failedJobsHistoryLimit | default 1 }}
  startingDeadlineSeconds: {{ $c.startingDeadlineSeconds | default 300 }}
  jobTemplate:
    spec:
      backoffLimit: {{ $c.backoffLimit | default 0 }}
      {{- with $c.activeDeadlineSeconds }}
      activeDeadlineSeconds: {{ . }}
      {{- end }}
      template:
        metadata:
          labels: {{- include "app.labels" $root | nindent 12 }}
            app.kubernetes.io/component: cronjob-{{ $n }}
        spec: {{- include "app.podSpec" (dict "root" $root "s" $c "what" (printf "cronjobs.%s.resources" $n) "restart" "Never") | nindent 10 }}
{{- end }}
{{- end -}}

{{/* Sync hook Job at wave -1: after the ServiceAccount and secrets (wave -2 / earlier), before the Deployments (wave 0),
     so it also works on a first install, which a PreSync hook does not. No TTL: BeforeHookCreation removes the previous Job. */}}
{{- define "app.migrations" -}}
{{- $m := .Values.migrations | default dict -}}
{{- if or $m.enabled $m.command -}}
---
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "app.fullname" . }}-migrations
  labels: {{- include "app.labels" . | nindent 4 }}
  annotations:
    argocd.argoproj.io/hook: Sync
    argocd.argoproj.io/sync-wave: "-1"
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  backoffLimit: 0
  activeDeadlineSeconds: {{ $m.activeDeadlineSeconds | default 600 }}
  template:
    metadata:
      labels: {{- include "app.labels" . | nindent 8 }}
        app.kubernetes.io/component: migrations
    spec: {{- include "app.podSpec" (dict "root" . "s" $m "what" "migrations.resources" "restart" "Never") | nindent 6 }}
{{- end -}}
{{- end -}}
