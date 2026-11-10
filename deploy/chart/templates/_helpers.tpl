{{- define "hub.rootHostname" -}}
root.{{ .Values.hostname }}
{{- end }}

{{- define "hub.issuerRef" -}}
{{- if .Values.tls.issuerRef.name -}}
{{ toYaml .Values.tls.issuerRef }}
{{- else -}}
group: cert-manager.io
kind: Issuer
name: selfsigned
{{- end }}
{{- end }}

{{- /* The oidc block of a RootShard's or FrontProxy's auth. */}}
{{- define "hub.oidc" -}}
{{- with .Values.oidc }}
{{- if .issuerURL }}
oidc:
  issuerURL: {{ .issuerURL }}
  clientID: {{ .clientID }}
  usernameClaim: {{ .usernameClaim }}
  groupsClaim: {{ .groupsClaim }}
  {{- if .caSecret.name }}
  # key is documented to default to ca.crt, but the operator does not
  # apply that default and kcp then fails to start.
  caFileRef:
    name: {{ .caSecret.name }}
    key: {{ .caSecret.key }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{- /* A deploymentTemplate with the hostAliases, if any. */}}
{{- define "hub.deploymentTemplate" -}}
{{- if .Values.hostAliases }}
deploymentTemplate:
  spec:
    template:
      spec:
        hostAliases:
          {{- toYaml .Values.hostAliases | nindent 10 }}
{{- end }}
{{- end }}
