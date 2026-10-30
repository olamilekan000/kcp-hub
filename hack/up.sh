#!/usr/bin/env bash
# Creates a kind cluster and installs kcp in it, reachable from the host at
# https://kcp.localhost:8443. Safe to run again on an existing cluster.

set -euo pipefail

CLUSTER_NAME=${CLUSTER_NAME:-kcp-hub}
CERT_MANAGER_VERSION=v1.19.2
ENVOY_GATEWAY_VERSION=v1.7.0

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DEPLOY=$ROOT/deploy/local
STATE=$ROOT/.hub

# The cluster gets a kubeconfig of its own, so this neither depends on nor
# changes whatever KUBECONFIG points at, including the admin kubeconfig
# written below.
mkdir -p "$STATE"
export KUBECONFIG=$STATE/kind.kubeconfig
KUBECTL=(kubectl --context "kind-$CLUSTER_NAME")

step() { printf '\n==> %s\n' "$*"; }

for tool in docker kind kubectl helm curl; do
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

step "Dex"
"${KUBECTL[@]}" apply -k "$DEPLOY/dex"
"${KUBECTL[@]}" -n dex wait certificate/dex-ca certificate/dex-tls --for=condition=Ready --timeout=2m
"${KUBECTL[@]}" -n dex get secret dex-ca -o jsonpath='{.data.ca\.crt}' | base64 -d >"$STATE/dex-ca.crt"
# kcp reads the CA from its own namespace, and has to find it before its
# pods start.
"${KUBECTL[@]}" create namespace kcp --dry-run=client -o yaml | "${KUBECTL[@]}" apply -f -
"${KUBECTL[@]}" -n kcp create secret generic dex-ca --from-file=ca.crt="$STATE/dex-ca.crt" \
  --dry-run=client -o yaml | "${KUBECTL[@]}" apply -f -
"${KUBECTL[@]}" -n dex rollout status deployment/dex --timeout=5m

step "kcp"
"${KUBECTL[@]}" apply -k "$DEPLOY/kcp"
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
    token=$(kubectl --kubeconfig "$STATE/${check_user%%@*}.kubeconfig" config view --raw \
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

missing=()
for host in kcp.localhost root.kcp.localhost dex.kcp.localhost; do
  grep -Eq "^[^#]*[[:space:]]$host([[:space:]]|\$)" /etc/hosts || missing+=("$host")
done

cat <<EOF

kcp is up at https://kcp.localhost:8443

  export KUBECONFIG=$STATE/admin.kubeconfig
  kubectl get workspaces

Dex is the sign-in provider at https://dex.kcp.localhost:8443/dex. To work
as one of its test users (password "password"):

  make login EMAIL=alice@team-a.example.com
  export KUBECONFIG=$STATE/alice.kubeconfig
  kubectl auth whoami
EOF

if [ ${#missing[@]} -gt 0 ]; then
  cat <<EOF

Some tools cannot resolve the .localhost names without help. If kubectl
answers "no such host", add this line to /etc/hosts:

  127.0.0.1 ${missing[*]}
EOF
fi
