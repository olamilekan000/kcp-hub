# Installing in your cluster

This guide installs kcp hub in a Kubernetes cluster you already run, with
your own domain and your own sign-in provider. To try kcp hub on your laptop
first, see [Getting started](getting-started.md).

kcp hub is installed with the Helm chart in [`deploy/chart`](../deploy/chart).
`make up` installs the same chart, with the settings in
[`deploy/local/values.yaml`](../deploy/local/values.yaml).

## What you need

- A Kubernetes cluster, and `kubectl` and [Helm](https://helm.sh) pointed
  at it.
- A domain you can add DNS records to. This guide uses `kcp.example.com`.
- An OpenID Connect (OIDC) provider your users sign in with, such as Okta,
  Microsoft Entra ID, Keycloak or Dex. See [The OIDC client](#the-oidc-client)
  for what it has to allow.
- A copy of this repository, for the chart:

  ```sh
  git clone https://github.com/olamilekan000/kcp-hub.git
  cd kcp-hub
  ```

The steps below also install what kcp hub runs on: cert-manager, a Gateway
API gateway, etcd and kcp-operator. Skip any you already have.

## 1. cert-manager

kcp-operator uses cert-manager to create kcp's certificates.

```sh
helm upgrade --install cert-manager cert-manager \
  --repo https://charts.jetstack.io --version v1.19.2 \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true --wait
```

## 2. A gateway with TLS passthrough

kcp checks client certificates and tokens itself, so it terminates TLS
itself too. The gateway in front of it has to pass TLS through unopened,
with a `TLSRoute`. This uses [Envoy Gateway](https://gateway.envoyproxy.io);
any Gateway API implementation that supports `TLSRoute` works.

```sh
helm upgrade --install envoy oci://registry-1.docker.io/envoyproxy/gateway-helm \
  --version v1.7.0 --namespace envoy-gateway-system --create-namespace --wait
```

Then create a Gateway with a passthrough listener:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: eg
  namespace: envoy-gateway-system
spec:
  gatewayClassName: eg
  listeners:
    - name: passthrough
      protocol: TLS
      port: 443
      tls:
        mode: Passthrough
      allowedRoutes:
        namespaces:
          from: All
```

Save it as `gateway.yaml` and apply it:

```sh
kubectl apply -f gateway.yaml
```

## 3. etcd

kcp stores its data in etcd. Any etcd that kcp can reach works. For a single
member, enough to start with:

```sh
kubectl apply -k deploy/local/etcd
kubectl -n kcp-etcd rollout status statefulset/etcd --timeout=5m
```

That etcd is reached at `http://etcd.kcp-etcd.svc.cluster.local:2379`, which
is the chart's default. For your own, set `kcp.etcdEndpoints`.

## 4. kcp-operator

kcp-operator runs kcp's shard and front-proxy from the objects the chart
creates.

```sh
kubectl apply --server-side -k deploy/local/kcp-operator
kubectl -n kcp-operator-system rollout status deployment --timeout=5m
```

## 5. DNS

Point these names at the gateway's address. `kubectl -n envoy-gateway-system
get gateway eg` shows it once the gateway is ready.

| Name | What it is |
|---|---|
| `kcp.example.com` | kcp's front-proxy, for `kubectl` and the virtual workspaces |
| `root.kcp.example.com` | kcp's root shard |
| `console.kcp.example.com` | the web console |

## 6. The OIDC client

Create a client in your OIDC provider for kcp hub. kcp, the console and the
virtual workspaces all use this one client.

- **Public, with PKCE.** The console and `kubectl` run on the user's machine
  and cannot keep a secret.
- **Redirect URI** `https://console.kcp.example.com/callback`, for the
  console. Add `http://localhost:8000/callback` too, for signing in from the
  terminal.
- **Claims.** The ID token has to carry the user's name and groups. The
  chart expects them in the `email` and `groups` claims; set
  `oidc.usernameClaim` and `oidc.groupsClaim` if yours differ.
- **Scopes.** The console asks for `openid email groups`. If your provider
  rejects a scope, for example `groups`, set `console.oidcScopes`.

Note the issuer URL and the client ID.

## 7. Settings

Write your settings to a file, for example `values.yaml`:

```yaml
hostname: kcp.example.com
port: 443

# The tenancy and marketplace images. A contrib-virtual-workspaces
# release such as v0.2.0 is tagged 0.2.0.
contrib:
  tag: "0.2.0"

oidc:
  issuerURL: https://login.example.com
  clientID: kcp-hub

# Who may manage tenants and the producer catalog: users and groups as
# your OIDC provider names them.
platformAdmins:
  users:
    - you@example.com
  groups: []

# Let any signed-in user create their own tenant.
tenancy:
  selfServiceTenants: true

gateway:
  parentRef:
    name: eg
    namespace: envoy-gateway-system

console:
  tls:
    # A cert-manager issuer browsers trust, such as Let's Encrypt.
    # Without one, the console's certificate is self-signed.
    issuerRef:
      group: cert-manager.io
      kind: ClusterIssuer
      name: letsencrypt
```

[`deploy/chart/values.yaml`](../deploy/chart/values.yaml) lists every
setting, with what it does. Two more you may need:

- `oidc.caSecret`, if your OIDC provider's certificate is not publicly
  trusted. It names a Secret in the release namespace with its CA.
- `hostAliases`, if the names in step 5 do not resolve to the gateway from
  inside the cluster. kcp's pods have to reach `kcp.example.com` and your
  OIDC provider.

## 8. Install

```sh
helm upgrade --install kcp-hub deploy/chart \
  --namespace kcp --create-namespace -f values.yaml
```

kcp takes a few minutes to start, longer the first time while its image
downloads. kcp-operator creates kcp's deployments once the chart is in, so
wait for them in this order:

```sh
kubectl -n kcp wait kubeconfig/admin --for=condition=Available --timeout=10m
kubectl -n kcp rollout status deployment root-kcp --timeout=15m
kubectl -n kcp rollout status deployment frontproxy-front-proxy --timeout=10m
kubectl -n kcp rollout status deployment tenancy-virtual-workspace --timeout=10m
kubectl -n kcp rollout status deployment marketplace-virtual-workspace --timeout=10m
```

The virtual workspaces set tenancy and the marketplace up in kcp before
they start. The tenancy and marketplace operators restart until that is
done, so a few restarts are expected. After the last restart they can take
a few minutes more to come up.

## 9. Check it works

The chart creates a kubeconfig for kcp's admin, in the Secret
`kcp-admin-kubeconfig`:

```sh
kubectl -n kcp get secret kcp-admin-kubeconfig -o jsonpath='{.data.kubeconfig}' \
  | base64 -d >admin.kubeconfig
kubectl --kubeconfig admin.kubeconfig get workspaces
```

It lists `tenancy` and `marketplace`. Keep `admin.kubeconfig` safe: it can
do anything in kcp.

Then open `https://console.kcp.example.com` and sign in as one of the
platform admins. [Getting started](getting-started.md#5-create-a-tenant-and-a-project)
walks through creating a tenant and a project, enabling an API and
publishing one. The catalog starts empty here: `make up` adds the example
Widgets API, the chart does not.

## Upgrading

Change `values.yaml`, or pull a newer version of this repository, and run
the `helm upgrade --install` command from step 8 again.

## Uninstalling

```sh
helm uninstall kcp-hub --namespace kcp
```

This removes kcp hub but not its data, which is in etcd. Delete etcd's data
too to start again from nothing.
