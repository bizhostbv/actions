{{- define "app.deployment" -}}
{{- include "app.scalingCheck" . -}}
{{- $a := .Values.autoscaling | default dict -}}
{{- $scaled := or (($a.hpa | default dict).enabled) (($a.keda | default dict).enabled) -}}
{{- $tag := required "image.tag is required (pin the version, e.g. 1.2.3@sha256:...)" (.Values.image).tag -}}
{{- $repo := required "image.repository is required" (.Values.image).repository -}}
{{- $probe := required "readinessProbe is required: a Deployment without one takes traffic before it is ready" .Values.readinessProbe -}}
{{- $res := deepCopy (.Values.resources | default dict) -}}
{{- $req := required "resources.requests is required (cpu and memory)" $res.requests -}}
{{- $lim := $res.limits | default dict -}}
{{- if and (not $lim.memory) $req.memory -}}{{- $_ := set $lim "memory" $req.memory -}}{{- end -}}
{{- $_ := set $res "limits" $lim -}}
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
    matchLabels: {{- include "app.selectorLabels" . | nindent 6 }}
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
      {{- with .Values.podAnnotations }}
      annotations: {{- toYaml . | nindent 8 }}
      {{- end }}
    spec:
      serviceAccountName: {{ include "app.serviceAccountName" . }}
      imagePullSecrets: {{- toYaml (.Values.imagePullSecrets | default (list (dict "name" "harbor-pull"))) | nindent 8 }}
      securityContext: {{- toYaml (.Values.podSecurityContext | default (dict "runAsNonRoot" true "runAsUser" 1000 "runAsGroup" 1000 "fsGroup" 1000)) | nindent 8 }}
      containers:
        - name: {{ .Values.containerName | default "app" }}
          image: "{{ $repo }}:{{ $tag }}"
          imagePullPolicy: {{ (.Values.image).pullPolicy | default "IfNotPresent" }}
          {{- with .Values.command }}
          command: {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.args }}
          args: {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.env }}
          env: {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.envFrom }}
          envFrom: {{- toYaml . | nindent 12 }}
          {{- end }}
          ports:
            {{- range (.Values.ports | default (list (dict "name" "http" "containerPort" 8080))) }}
            - {{- toYaml . | nindent 14 }}
            {{- end }}
            {{- with (.Values.metrics | default dict).port }}
            - name: metrics
              containerPort: {{ . }}
            {{- end }}
          readinessProbe: {{- toYaml $probe | nindent 12 }}
          {{- with .Values.livenessProbe }}
          livenessProbe: {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.startupProbe }}
          startupProbe: {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.lifecycle }}
          lifecycle: {{- toYaml . | nindent 12 }}
          {{- end }}
          resources: {{- toYaml $res | nindent 12 }}
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: [ALL]
            readOnlyRootFilesystem: {{ .Values.readOnlyRootFilesystem | default false }}
          {{- with .Values.volumeMounts }}
          volumeMounts: {{- toYaml . | nindent 12 }}
          {{- end }}
        {{- with .Values.sidecars }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      {{- with .Values.volumes }}
      volumes: {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.nodeSelector }}
      nodeSelector: {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations: {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity: {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.extraPodSpec }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
{{- end -}}
