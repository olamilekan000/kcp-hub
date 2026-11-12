#!/usr/bin/env bash
# Creates a kind cluster and installs kcp in it, reachable from the host at
# https://kcp.localhost:8443. Safe to run again on an existing cluster.

set -euo pipefail

CLUSTER_NAME=${CLUSTER_NAME:-kcp-hub}

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

console_image_override=${CONSOLE_IMAGE:-}
# shellcheck source=/dev/null
. "$ROOT/versions.env"
CONSOLE_IMAGE=${console_image_override:-$CONSOLE_IMAGE}

# Release v0.2.0 is published as 0.2.0, a commit as sha-<commit>.
CONTRIB_REPO=https://github.com/kcp-dev/contrib-virtual-workspaces
if [[ $CONTRIB_VERSION == v[0-9]* ]]; then
  CONTRIB_TAG=${CONTRIB_VERSION#v}
else
  CONTRIB_TAG=sha-$CONTRIB_VERSION
fi
TENANCY_IMAGE=ghcr.io/kcp-dev/contrib-virtual-workspaces/tenancy-vw:$CONTRIB_TAG
MARKETPLACE_IMAGE=ghcr.io/kcp-dev/contrib-virtual-workspaces/marketplace-vw:$CONTRIB_TAG

DEPLOY=$ROOT/deploy/local
STATE=$ROOT/.hub

# The cluster gets a kubeconfig of its own, so this neither depends on nor
# changes whatever KUBECONFIG points at, including the admin kubeconfig
# written below.
mkdir -p "$STATE"
export KUBECONFIG=$STATE/kind.kubeconfig
KUBECTL=(kubectl --context "kind-$CLUSTER_NAME")

step() { printf '\n==> %s\n' "$*"; }

# Makes a contrib-virtual-workspaces image available in the cluster:
# pulled by the cluster if it is published, otherwise built from
# CONTRIB_VERSION and loaded. Published images are not loaded: they are
# multi-platform, and kind cannot load one that docker pulled for a
# single platform.
contrib_image() {
  local target=$1 image=$2 src=$STATE/src/contrib-virtual-workspaces
  if docker exec "$CLUSTER_NAME-control-plane" crictl inspecti "$image" >/dev/null 2>&1; then
    echo "$image is already in the cluster"
    return
  fi
  if docker manifest inspect "$image" >/dev/null 2>&1; then
    echo "$image is published; the cluster pulls it"
    return
  fi
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    echo "$image is not published; building it from $CONTRIB_REPO at $CONTRIB_VERSION"
    if [ ! -d "$src/.git" ]; then
      git init -q "$src"
      git -C "$src" remote add origin "$CONTRIB_REPO"
    fi
    git -C "$src" fetch -q --depth 1 origin "$CONTRIB_VERSION"
    git -C "$src" checkout -q --detach FETCH_HEAD
    docker build --target "$target" -t "$image" "$src"
  fi
  kind load docker-image "$image" --name "$CLUSTER_NAME"
}

# Dex and the console read their certificate, and Dex its config, once at
# startup. Recording a checksum of them on the pod template restarts the
# Deployment when they change, and does nothing when they have not.
restart_on_change() {
  local namespace=$1 deployment=$2 secret=$3 configmap=${4:-} extra=${5:-} sum
  sum=$({
    "${KUBECTL[@]}" -n "$namespace" get secret "$secret" -o jsonpath='{.data.tls\.crt}'
    if [ -n "$configmap" ]; then
      "${KUBECTL[@]}" -n "$namespace" get configmap "$configmap" -o jsonpath='{.data}'
    fi
    echo "$extra"
  } | shasum | cut -c1-16)
  "${KUBECTL[@]}" -n "$namespace" patch deployment "$deployment" --type=merge \
    -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"hub.kcp.io/inputs\":\"$sum\"}}}}}"
}

# Runs kubectl as the kcp admin in one kcp workspace.
in_workspace() {
  local ws=$1
  shift
  kubectl --kubeconfig "$STATE/admin.kubeconfig" --server "https://kcp.localhost:8443/clusters/$ws" "$@"
}

# Waits for a Deployment that kcp-operator creates, so it may not exist yet.
wait_deployment() {
  local name=$1
  for _ in $(seq 1 60); do
    "${KUBECTL[@]}" -n kcp get deployment "$name" >/dev/null 2>&1 && break
    sleep 2
  done
  "${KUBECTL[@]}" -n kcp rollout status deployment "$name" --timeout=10m
}

for tool in docker kind kubectl helm curl git; do
  command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done

step "kind cluster $CLUSTER_NAME"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "already exists"
  kind export kubeconfig --name "$CLUSTER_NAME"
else
  if curl -so /dev/null --max-time 2 http://127.0.0.1:8443; then
    echo "port 8443 is already in use; stop whatever is listening there first" >&2
    exit 1
  fi
  kind create cluster --name "$CLUSTER_NAME" --config "$DEPLOY/kind.yaml"
fi

step "cert-manager $CERT_MANAGER_VERSION"
helm upgrade --install cert-manager cert-manager \
  --kube-context "kind-$CLUSTER_NAME" \
  --repo https://charts.jetstack.io --version "$CERT_MANAGER_VERSION" \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true --wait

step "Envoy Gateway $ENVOY_GATEWAY_VERSION"
helm upgrade --install envoy oci://registry-1.docker.io/envoyproxy/gateway-helm \
  --kube-context "kind-$CLUSTER_NAME" \
  --version "$ENVOY_GATEWAY_VERSION" \
  --namespace envoy-gateway-system --create-namespace --wait
"${KUBECTL[@]}" apply -f "$DEPLOY/gateway.yaml"

step "etcd"
"${KUBECTL[@]}" apply -k "$DEPLOY/etcd"
"${KUBECTL[@]}" -n kcp-etcd rollout status statefulset/etcd --timeout=5m

step "kcp-operator"
# Server-side, because the CRDs are too large for the annotation a
# client-side apply keeps.
"${KUBECTL[@]}" apply --server-side --force-conflicts -k "$DEPLOY/kcp-operator"
"${KUBECTL[@]}" wait crd/rootshards.operator.kcp.io --for=condition=Established --timeout=2m
"${KUBECTL[@]}" -n kcp-operator-system rollout status deployment --timeout=5m

step "local CA"
"${KUBECTL[@]}" apply -k "$DEPLOY/ca"
"${KUBECTL[@]}" -n cert-manager wait certificate/hub-ca --for=condition=Ready --timeout=2m
"${KUBECTL[@]}" -n cert-manager get secret hub-ca -o jsonpath='{.data.ca\.crt}' | base64 -d >"$STATE/ca.crt"
# kcp and the virtual workspaces read the CA from the kcp namespace, and
# have to find it before their pods start.
"${KUBECTL[@]}" create namespace kcp --dry-run=client -o yaml | "${KUBECTL[@]}" apply -f -
"${KUBECTL[@]}" -n kcp create secret generic hub-ca --from-file=ca.crt="$STATE/ca.crt" \
  --dry-run=client -o yaml | "${KUBECTL[@]}" apply -f -

step "Dex"
"${KUBECTL[@]}" apply -k "$DEPLOY/dex"
"${KUBECTL[@]}" -n dex wait certificate/dex-tls --for=condition=Ready --timeout=2m
restart_on_change dex dex dex-tls dex
"${KUBECTL[@]}" -n dex rollout status deployment/dex --timeout=5m

step "kcp"
contrib_image tenancy-vw "$TENANCY_IMAGE"
contrib_image marketplace-vw "$MARKETPLACE_IMAGE"
console_image=${CONSOLE_IMAGE:-kcp-hub/console:dev}
if [ -n "$CONSOLE_IMAGE" ]; then
  docker pull "$console_image"
else
  docker build -t "$console_image" "$ROOT/console"
fi
# Loaded rather than pulled by the cluster, so a moved tag such as :main
# reaches it too, through the image ID in the console step.
kind load docker-image "$console_image" --name "$CLUSTER_NAME"
helm upgrade --install kcp-hub "$ROOT/deploy/chart" \
  --kube-context "kind-$CLUSTER_NAME" --namespace kcp \
  -f "$DEPLOY/values.yaml" --set contrib.tag="$CONTRIB_TAG" \
  --set console.image.repository="${console_image%:*}" --set console.image.tag="${console_image##*:}"
"${KUBECTL[@]}" -n kcp wait kubeconfig/admin --for=condition=Available --timeout=10m
"${KUBECTL[@]}" -n kcp get secret kcp-admin-kubeconfig -o jsonpath='{.data.kubeconfig}' \
  | base64 -d >"$STATE/admin.kubeconfig"

step "waiting for https://kcp.localhost:8443"
for _ in $(seq 1 60); do
  if curl -sk --max-time 3 --resolve kcp.localhost:8443:127.0.0.1 \
    -o /dev/null -w '%{http_code}' https://kcp.localhost:8443/readyz | grep -q 200; then
    ready=1
    break
  fi
  sleep 5
done
if [ -z "${ready:-}" ]; then
  echo "kcp did not become reachable on https://kcp.localhost:8443" >&2
  exit 1
fi

step "signing in through Dex"
# Retried, because on an existing cluster kcp may still be rolling out with
# the new authentication settings.
check_user=admin@platform.example.com
for _ in $(seq 1 30); do
  if "$ROOT/hack/login.sh" "$check_user" >/dev/null; then
    token=$(kubectl --kubeconfig "$STATE/users/${check_user%%@*}.kubeconfig" config view --raw \
      -o jsonpath='{.users[0].user.token}')
    whoami=$(curl -sk --max-time 5 --resolve kcp.localhost:8443:127.0.0.1 \
      -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
      -d '{"apiVersion":"authentication.k8s.io/v1","kind":"SelfSubjectReview"}' \
      https://kcp.localhost:8443/clusters/root/apis/authentication.k8s.io/v1/selfsubjectreviews || true)
    if printf '%s' "$whoami" | grep -q "\"username\": *\"$check_user\""; then
      signed_in=1
      break
    fi
  fi
  sleep 5
done
if [ -z "${signed_in:-}" ]; then
  echo "kcp did not accept a Dex token for $check_user; last answer: ${whoami:-none}" >&2
  exit 1
fi
echo "kcp accepts Dex tokens ($check_user)"

step "tenancy"
wait_deployment tenancy-virtual-workspace
wait_deployment tenancy-operator

review=$(curl -sk --max-time 10 --resolve kcp.localhost:8443:127.0.0.1 \
  -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
  -d '{"apiVersion":"tenancy.platform.kcp.io/v1alpha1","kind":"SelfTenancyReview"}' \
  -o /dev/null -w '%{http_code}' \
  https://kcp.localhost:8443/services/tenancy/apis/tenancy.platform.kcp.io/v1alpha1/selftenancyreviews || true)
if [ "$review" != 201 ] && [ "$review" != 200 ]; then
  echo "the tenancy virtual workspace did not answer on /services/tenancy (HTTP $review)" >&2
  exit 1
fi
echo "tenancy answers at https://kcp.localhost:8443/services/tenancy"

step "marketplace"
wait_deployment marketplace-virtual-workspace
wait_deployment marketplace-operator

echo "publishing the example producer"
in_workspace root:marketplace:catalog apply -f "$DEPLOY/marketplace/example/producer.yaml"
for _ in $(seq 1 60); do
  producer_ws=$(in_workspace root:marketplace:catalog get producer acme \
    -o jsonpath='{.status.workspacePath}' 2>/dev/null || true)
  [ -n "$producer_ws" ] && break
  sleep 2
done
if [ -z "$producer_ws" ]; then
  echo "the marketplace operator did not create a workspace for the example producer" >&2
  exit 1
fi
in_workspace "$producer_ws" apply -f "$DEPLOY/marketplace/example/widgets.yaml"

for _ in $(seq 1 60); do
  offerings=$(curl -sk --max-time 10 --resolve kcp.localhost:8443:127.0.0.1 \
    -H "Authorization: Bearer $token" \
    https://kcp.localhost:8443/services/marketplace/apis/marketplace.platform.kcp.io/v1alpha1/offerings || true)
  if printf '%s' "$offerings" | grep -q widgets.acme.example; then
    listed=1
    break
  fi
  sleep 2
done
if [ -z "${listed:-}" ]; then
  echo "the example API did not show up in the catalog; last answer: ${offerings:-none}" >&2
  exit 1
fi
echo "the catalog at https://kcp.localhost:8443/services/marketplace lists widgets.acme.example"

step "console"
"${KUBECTL[@]}" -n kcp wait certificate/console-tls --for=condition=Ready --timeout=2m
restart_on_change kcp console console-tls "" "$(docker image inspect -f '{{.Id}}' "$console_image")"
"${KUBECTL[@]}" -n kcp rollout status deployment/console --timeout=5m

# Through the console, so this checks its certificate and its route to kcp.
for _ in $(seq 1 30); do
  via_console=$(curl -s --max-time 10 --cacert "$STATE/ca.crt" --resolve console.kcp.localhost:8443:127.0.0.1 \
    -H "Authorization: Bearer $token" \
    https://console.kcp.localhost:8443/services/marketplace/apis/marketplace.platform.kcp.io/v1alpha1/offerings \
    || true)
  if printf '%s' "$via_console" | grep -q widgets.acme.example; then
    console_ok=1
    break
  fi
  sleep 2
done
if [ -z "${console_ok:-}" ]; then
  echo "the console at https://console.kcp.localhost:8443 did not reach kcp; last answer: ${via_console:-none}" >&2
  exit 1
fi
echo "the console at https://console.kcp.localhost:8443 reaches kcp"

missing=()
for host in kcp.localhost root.kcp.localhost dex.kcp.localhost console.kcp.localhost; do
  grep -Eq "^[^#]*[[:space:]]$host([[:space:]]|\$)" /etc/hosts || missing+=("$host")
done

cat <<EOF

kcp is up at https://kcp.localhost:8443

  export KUBECONFIG=$STATE/admin.kubeconfig
  kubectl get workspaces

The console is at https://console.kcp.localhost:8443. Its certificate and
Dex's come from a local CA; trust $STATE/ca.crt in your browser or
system, or accept the warnings on both sites once.

Dex is the sign-in provider at https://dex.kcp.localhost:8443/dex. To work
as one of its test users (password "password"):

  make login EMAIL=alice@team-a.example.com
  export KUBECONFIG=$STATE/users/alice.kubeconfig
  kubectl auth whoami
EOF

if [ ${#missing[@]} -gt 0 ]; then
  cat <<EOF

Some tools cannot resolve the .localhost names without help. If kubectl
answers "no such host", add this line to /etc/hosts:

  127.0.0.1 ${missing[*]}
EOF
fi
