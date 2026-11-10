#!/usr/bin/env bash
# Checks that a platform started with make up works for a user: a test user
# signs in, gets a tenant and a project in it, enables the example API from
# the catalog in the project, and creates an object through it.
#
#   make test

set -euo pipefail

EMAIL=${SMOKE_USER:-alice@team-a.example.com}
OFFERING=${SMOKE_OFFERING:-acme.widgets.acme.example}
# Tenant names are shared by everyone, so each run asks for a new one.
TENANT=smoke-$(date +%s)
PROJECT=app

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STATE=$ROOT/.hub
KCP=https://kcp.localhost:8443
TENANCY=$KCP/services/tenancy/apis/tenancy.platform.kcp.io/v1alpha1
MARKETPLACE=$KCP/services/marketplace/apis/marketplace.platform.kcp.io/v1alpha1

for tool in kubectl curl jq; do
  command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done

step() { printf '\n==> %s\n' "$*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# Calls kcp as the test user. Fails on an HTTP error, printing the answer.
api() {
  local method=$1 url=$2 body=${3:-}
  local args=(-sS --fail-with-body --cacert "$STATE/kcp-ca.crt"
    --resolve kcp.localhost:8443:127.0.0.1
    -H "Authorization: Bearer $token" -H 'Content-Type: application/json' -X "$method")
  [ -n "$body" ] && args+=(-d "$body")
  curl "${args[@]}" "$url"
}

# Retries a check until it passes or about two minutes have gone by.
wait_for() {
  local what=$1
  shift
  for _ in $(seq 1 60); do
    "$@" >/dev/null 2>&1 && return 0
    sleep 2
  done
  fail "$what"
}

review() {
  api POST "$TENANCY/selftenancyreviews" \
    '{"apiVersion":"tenancy.platform.kcp.io/v1alpha1","kind":"SelfTenancyReview"}'
}

tenant_ready() { review | jq -e --arg t "$TENANT" '.status.tenants[]? | select(.name == $t and .cluster != "")'; }

project_cluster() {
  review | jq -er --arg t "$TENANT" --arg p "$PROJECT" \
    '.status.tenants[]? | select(.name == $t) | .projects[]? | select(.name == $p) | .cluster'
}

request_project() {
  api POST "$TENANCY/selfprojectrequests" "$(jq -nc --arg t "$TENANT" --arg p "$PROJECT" \
    '{apiVersion: "tenancy.platform.kcp.io/v1alpha1", kind: "SelfProjectRequest", spec: {tenant: $t, name: $p}}')" \
    | jq -e '.status.created == true'
}

binding_bound() {
  api GET "$KCP/clusters/$cluster/apis/apis.kcp.io/v1alpha2/apibindings/$OFFERING" \
    | jq -e '.status.phase == "Bound"'
}

[ -f "$STATE/admin.kubeconfig" ] || fail "$STATE/admin.kubeconfig is missing; run make up first"
kubectl --kubeconfig "$STATE/admin.kubeconfig" config view --raw --minify \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d >"$STATE/kcp-ca.crt"

step "$EMAIL signs in"
"$ROOT/hack/login.sh" "$EMAIL" >/dev/null
token=$(kubectl --kubeconfig "$STATE/users/${EMAIL%%@*}.kubeconfig" config view --raw \
  -o jsonpath='{.users[0].user.token}')
api POST "$KCP/clusters/root/apis/authentication.k8s.io/v1/selfsubjectreviews" \
  '{"apiVersion":"authentication.k8s.io/v1","kind":"SelfSubjectReview"}' \
  | jq -e --arg u "$EMAIL" '.status.userInfo.username == $u' >/dev/null \
  || fail "kcp does not see the token as $EMAIL"

step "tenant $TENANT"
api POST "$TENANCY/selftenantrequests" "$(jq -nc --arg t "$TENANT" \
  '{apiVersion: "tenancy.platform.kcp.io/v1alpha1", kind: "SelfTenantRequest", spec: {name: $t}}')" \
  | jq -e '.status.created == true' >/dev/null || fail "the tenant was not created"
wait_for "tenant $TENANT did not get a workspace" tenant_ready

step "project $PROJECT"
# Retried, because the user becomes the tenant's admin a moment after its
# workspace is ready.
wait_for "project $PROJECT was not created" request_project
wait_for "project $PROJECT did not get a workspace" project_cluster
cluster=$(project_cluster)

step "enabling $OFFERING in the project"
offering=$(api GET "$MARKETPLACE/offerings" | jq -c --arg o "$OFFERING" '.items[]? | select(.metadata.name == $o)')
[ -n "$offering" ] || fail "the catalog does not list $OFFERING"
binding=$(printf '%s' "$offering" | jq -c --arg n "$OFFERING" '{
  apiVersion: "apis.kcp.io/v1alpha2", kind: "APIBinding", metadata: {name: $n},
  spec: {
    reference: {export: {path: .workspacePath, name: .export}},
    permissionClaims: [(.claims // [])[] | {
      group: (.group // ""), resource, verbs: (.verbs // []), identityHash: (.identityHash // ""),
      selector: (if .matchLabels then {matchLabels} else {matchAll: true} end), state: "Accepted"}]
  }}')
api POST "$KCP/clusters/$cluster/apis/apis.kcp.io/v1alpha2/apibindings" "$binding" >/dev/null
wait_for "the APIBinding for $OFFERING did not become Bound" binding_bound

step "creating a Widget through the enabled API"
api POST "$KCP/clusters/$cluster/apis/acme.example/v1alpha1/widgets" \
  '{"apiVersion":"acme.example/v1alpha1","kind":"Widget","metadata":{"name":"smoke"},"spec":{"size":"small"}}' >/dev/null
api GET "$KCP/clusters/$cluster/apis/acme.example/v1alpha1/widgets/smoke" \
  | jq -e '.spec.size == "small"' >/dev/null || fail "the Widget did not read back"

printf '\nsmoke test passed: %s has tenant %s, project %s, and Widgets enabled in it\n' \
  "$EMAIL" "$TENANT" "$PROJECT"
