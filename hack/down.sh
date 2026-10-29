#!/usr/bin/env bash
# Deletes the kind cluster and the local state hack/up.sh created.

set -euo pipefail

CLUSTER_NAME=${CLUSTER_NAME:-kcp-hub}
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

kind delete cluster --name "$CLUSTER_NAME" --kubeconfig "$ROOT/.hub/kind.kubeconfig"
rm -rf "$ROOT/.hub"
