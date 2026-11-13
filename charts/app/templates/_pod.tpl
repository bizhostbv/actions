{{/* Resources with the memory limit defaulting to the request. Args: dict "s" spec "what" key-name-for-the-error. */}}
{{- define "app.resources" -}}
{{- $res := deepCopy (.s.resources | default dict) -}}
{{- $req := required (printf "%s.requests is required (cpu and memory)" .what) $res.requests -}}
{{- $lim := $res.limits | default dict -}}
{{- if and (not $lim.memory) $req.memory -}}{{- $_ := set $lim "memory" $req.memory -}}{{- end -}}
{{- $_ := set $res "limits" $lim -}}
{{- toYaml $res -}}
{{- end -}}

{{/* Selector labels of one component (web, worker-<name>, cronjob-<name>, migrations). Args: dict "root" . "component" "web". */}}
{{- define "app.componentSelector" -}}
{{ include "app.selectorLabels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/* Pod spec shared by web, workers, CronJobs and migrations: same image, env, envFrom, securityContext, pull secrets.
Args: dict "root" . "s" spec "what" key-name "web" bool "restart" Never|"" "grace" seconds|"" */}}
{{- define "app.podSpec" -}}
{{- $root := .root -}}{{- $s := .s -}}{{- $v := $root.Values -}}
{{- $tag := required "image.tag is required (pin the version, e.g. 1.2.3@sha256:...)" ($v.image).tag -}}
{{- $repo := required "image.repository is required" ($v.image).repository -}}
serviceAccountName: {{ include "app.serviceAccountName" $root }}
imagePullSecrets: {{- toYaml ($v.imagePullSecrets | default (list (dict "name" "harbor-pull"))) | nindent 2 }}
securityContext: {{- toYaml ($v.podSecurityContext | default (dict "runAsNonRoot" true "runAsUser" 1000 "runAsGroup" 1000 "fsGroup" 1000)) | nindent 2 }}
{{- with .restart }}
restartPolicy: {{ . }}
{{- end }}
{{- with .grace }}
terminationGracePeriodSeconds: {{ . }}
{{- end }}
containers:
  - name: {{ $v.containerName | default "app" }}
    image: "{{ $repo }}:{{ $tag }}"
    imagePullPolicy: {{ ($v.image).pullPolicy | default "IfNotPresent" }}
    {{- with $s.command }}
    command: {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with $s.args }}
    args: {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with $v.env }}
    env: {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with $v.envFrom }}
    envFrom: {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- if .web }}
    ports:
      {{- range ($v.ports | default (list (dict "name" "http" "containerPort" 8080))) }}
      - {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with ($v.metrics | default dict).port }}
      - name: metrics
        containerPort: {{ . }}
      {{- end }}
    readinessProbe: {{- toYaml (required "readinessProbe is required: a Deployment without one takes traffic before it is ready" $v.readinessProbe) | nindent 6 }}
    {{- with $v.startupProbe }}
    startupProbe: {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with $v.lifecycle }}
    lifecycle: {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- end }}
    {{- with $s.livenessProbe }}
    livenessProbe: {{- toYaml . | nindent 6 }}
    {{- end }}
    resources: {{- include "app.resources" (dict "s" $s "what" .what) | nindent 6 }}
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: [ALL]
      readOnlyRootFilesystem: {{ $v.readOnlyRootFilesystem | default false }}
    {{- with $v.volumeMounts }}
    volumeMounts: {{- toYaml . | nindent 6 }}
    {{- end }}
  {{- if .web }}
  {{- with $v.sidecars }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
  {{- end }}
{{- with $v.volumes }}
volumes: {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $v.nodeSelector }}
nodeSelector: {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $v.tolerations }}
tolerations: {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $v.affinity }}
affinity: {{- toYaml . | nindent 2 }}
{{- end }}
{{- if .web }}
{{- with $v.extraPodSpec }}
{{ toYaml . }}
{{- end }}
{{- end }}
{{- end -}}
