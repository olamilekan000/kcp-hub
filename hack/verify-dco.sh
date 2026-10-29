#!/usr/bin/env bash
# Fails if any non-merge commit in BASE..HEAD lacks a Signed-off-by line.
#
# Usage: hack/verify-dco.sh <base> [head]

set -euo pipefail

base=${1:?usage: $0 <base> [head]}
head=${2:-HEAD}

missing=0
while read -r sha; do
  if ! git log -1 --format=%B "$sha" | grep -qE '^Signed-off-by: .+ <.+>$'; then
    echo "missing Signed-off-by: $(git log -1 --format='%h %s' "$sha")"
    missing=1
  fi
done < <(git rev-list --no-merges "$base..$head")

if [ "$missing" -ne 0 ]; then
  cat <<'EOF'

Every commit needs a sign-off certifying the Developer Certificate of Origin
(see the DCO file). Add it to existing commits with:

  git rebase --signoff <base>
  git push --force-with-lease
EOF
  exit 1
fi

echo "All commits have Signed-off-by"
