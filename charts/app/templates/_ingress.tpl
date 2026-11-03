{{- define "app.ingress" -}}
{{- $i := .Values.ingress | default dict -}}
{{- if $i.enabled -}}
{{- $hosts := required "ingress.hosts is required when ingress.enabled (list of {host, paths: [{path, pathType}]})" $i.hosts -}}
{{- $issuer := ternary $i.clusterIssuer "lets-encrypt-cloudflare" (hasKey $i "clusterIssuer") -}}
{{- $tls := $i.tls | default dict -}}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "app.fullname" . }}
  labels:
    {{- include "app.labels" . | nindent 4 }}
    {{- if eq (toString $i.monitoring) "false" }}
    blackbox-exporter/ignore: "true"
    {{- end }}
  annotations:
    {{- with $issuer }}
    cert-manager.io/cluster-issuer: {{ . | quote }}
    {{- end }}
    {{- with $i.allowList }}
    haproxy.org/allow-list: {{ join "," . | quote }}
    {{- end }}
    {{- with $i.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  ingressClassName: {{ $i.className | default "haproxy" }}
  tls:
    - secretName: {{ $tls.secretName | default (printf "%s-tls" (include "app.fullname" .)) }}
      hosts:
        {{- range $hosts }}
        - {{ .host | quote }}
        {{- end }}
  rules:
    {{- range $hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths | default (list (dict "path" "/")) }}
          - path: {{ .path }}
            pathType: {{ .pathType | default "Prefix" }}
            backend:
              service:
                name: {{ include "app.fullname" $ }}
                port:
                  name: http
          {{- end }}
    {{- end }}
{{- end -}}
{{- end -}}
