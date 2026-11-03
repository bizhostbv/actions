{{- define "app.service" -}}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ include "app.fullname" . }}
  labels: {{- include "app.labels" . | nindent 4 }}
spec:
  type: ClusterIP
  selector: {{- include "app.componentSelector" (dict "root" . "component" "web") | nindent 4 }}
  ports:
    - name: http
      port: {{ (.Values.service | default dict).port | default 80 }}
      targetPort: {{ (.Values.service | default dict).targetPort | default "http" }}
    {{- with (.Values.metrics | default dict).port }}
    - name: metrics
      port: {{ . }}
      targetPort: metrics
    {{- end }}
{{- end -}}
