#!/usr/bin/env bash
# Signs a test user in through Dex, without a browser, and writes a
# kubeconfig that uses their token:
#
#   make login EMAIL=alice@team-a.example.com
#   export KUBECONFIG=$PWD/.hub/alice.kubeconfig
#   kubectl auth whoami
#
# Dex tokens expire after a day; run it again for a fresh one.

set -euo pipefail

EMAIL=${1:?usage: hack/login.sh <email> [password]}
PASSWORD=${2:-password}

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STATE=$ROOT/.hub
CA=$STATE/dex-ca.crt
ADMIN=$STATE/admin.kubeconfig

for file in "$CA" "$ADMIN"; do
  [ -f "$file" ] || { echo "$file is missing; run make up first" >&2; exit 1; }
done

response=$(curl -sS --cacert "$CA" --resolve dex.kcp.localhost:8443:127.0.0.1 \
  https://dex.kcp.localhost:8443/dex/token \
  --data-urlencode grant_type=password \
  --data-urlencode client_id=kcp \
  --data-urlencode "username=$EMAIL" \
  --data-urlencode "password=$PASSWORD" \
  --data-urlencode "scope=openid email groups profile")
token=$(printf '%s' "$response" | sed -n 's/.*"id_token":"\([^"]*\)".*/\1/p')
if [ -z "$token" ]; then
  echo "Dex did not issue a token for $EMAIL: $response" >&2
  exit 1
fi

# Same kcp endpoint as the admin kubeconfig, with the user's token instead
# of the admin's client certificate.
server=$(kubectl --kubeconfig "$ADMIN" config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')
ca_data=$(kubectl --kubeconfig "$ADMIN" config view --raw --minify \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

name=${EMAIL%%@*}
out=$STATE/$name.kubeconfig
umask 077
cat >"$out" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: kcp
    cluster:
      server: $server
      certificate-authority-data: $ca_data
users:
  - name: $EMAIL
    user:
      token: $token
contexts:
  - name: $name
    context:
      cluster: kcp
      user: $EMAIL
current-context: $name
EOF

echo "signed in as $EMAIL"
echo "  export KUBECONFIG=$out"
