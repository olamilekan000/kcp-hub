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

{{- /* A contrib-virtual-workspaces image, by component name. */}}
{{- define "hub.contribImage" -}}
{{ .ctx.Values.contrib.repository }}/{{ .name }}-vw:{{ required "contrib.tag is required" .ctx.Values.contrib.tag }}
{{- end }}

{{- /*
The three identities of a component, by component name. init needs an
admin to create the component's workspaces and exports, then grants the
server role to the virtual workspace and the operator, whose reach is
exactly what the component's exports give them.
*/}}
{{- define "hub.kubeconfigs" -}}
apiVersion: operator.kcp.io/v1alpha1
kind: Kubeconfig
metadata:
  name: {{ . }}-bootstrap
spec:
  username: kcp-admin
  groups:
    - system:kcp:admin
  validity: 8766h
  secretRef:
    name: {{ . }}-bootstrap-kubeconfig
  target:
    frontProxyRef:
      name: frontproxy
---
apiVersion: operator.kcp.io/v1alpha1
kind: Kubeconfig
metadata:
  name: {{ . }}-vw
spec:
  username: {{ . }}-vw
  validity: 8766h
  targetWorkspace: root:{{ . }}:controllers
  secretRef:
    name: {{ . }}-vw-kubeconfig
  target:
    frontProxyRef:
      name: frontproxy
---
apiVersion: operator.kcp.io/v1alpha1
kind: Kubeconfig
metadata:
  name: {{ . }}-operator
spec:
  username: {{ . }}-operator
  validity: 8766h
  secretRef:
    name: {{ . }}-operator-kubeconfig
  target:
    frontProxyRef:
      name: frontproxy
{{- end }}

{{- /* The init container of a component's VirtualWorkspace. */}}
{{- define "hub.initContainer" -}}
- name: init
  command: ["/{{ .name }}-vw", "init"]
  kubeconfigSecretRef:
    name: {{ .name }}-bootstrap-kubeconfig
  args:
    - --kubeconfig=/etc/kcp/init-kubeconfig/kubeconfig
    - --server-user={{ .name }}-vw
    - --server-user={{ .name }}-operator
    {{- range .ctx.Values.platformAdmins.users }}
    - --platform-admin-user={{ . }}
    {{- end }}
    {{- range .ctx.Values.platformAdmins.groups }}
    - --platform-admin-group={{ . }}
    {{- end }}
{{- end }}

{{- /*
The OIDC flags of a virtual workspace. They must match kcp's, so a token
names the same user there as it does in kcp.
*/}}
{{- define "hub.oidcArgs" -}}
{{- with .Values.oidc }}
{{- if .issuerURL }}
- --oidc-issuer-url={{ .issuerURL }}
- --oidc-client-id={{ .clientID }}
- --oidc-username-claim={{ .usernameClaim }}
- --oidc-groups-claim={{ .groupsClaim }}
{{- if .caSecret.name }}
- --oidc-ca-file=/etc/oidc/{{ .caSecret.key }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{- /* The volume with the OIDC issuer's CA, if any, for a virtual workspace. */}}
{{- define "hub.oidcVolume" -}}
{{- if and .Values.oidc.issuerURL .Values.oidc.caSecret.name }}
extraVolumes:
  - name: oidc-ca
    secret:
      secretName: {{ .Values.oidc.caSecret.name }}
extraVolumeMounts:
  - name: oidc-ca
    mountPath: /etc/oidc
    readOnly: true
{{- end }}
{{- end }}

{{- /*
A component's operator. If it starts before init has run, it exits and
is restarted until init is done.
*/}}
{{- define "hub.operator" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .name }}-operator
  labels:
    app: {{ .name }}-operator
spec:
  replicas: 1
  selector:
    matchLabels:
      app: {{ .name }}-operator
  template:
    metadata:
      labels:
        app: {{ .name }}-operator
    spec:
      containers:
        - name: operator
          image: {{ include "hub.contribImage" . }}
          args:
            - operator
            - --kubeconfig=/etc/{{ .name }}/kubeconfig
            - --workspace-path=root:{{ .name }}:controllers
            {{- toYaml .args | nindent 12 }}
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
          volumeMounts:
            - name: kubeconfig
              mountPath: /etc/{{ .name }}
              readOnly: true
      volumes:
        - name: kubeconfig
          secret:
            secretName: {{ .name }}-operator-kubeconfig
      {{- with .ctx.Values.hostAliases }}
      hostAliases:
        {{- toYaml . | nindent 8 }}
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
