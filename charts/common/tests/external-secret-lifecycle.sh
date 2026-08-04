#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
chart_dir="$(cd -- "$script_dir/.." && pwd)"
values_file="$chart_dir/test-values.yaml"

rendered_with_secret="$(helm template lifecycle "$chart_dir" --values "$values_file")"
external_secret="$(
  printf '%s\n' "$rendered_with_secret" |
    awk 'BEGIN { RS = "---" } /kind: ExternalSecret/ { print }'
)"

if [[ -z "$external_secret" ]]; then
  echo "expected an ExternalSecret in the rendered manifest" >&2
  exit 1
fi

if grep -q 'helm\.sh/hook' <<<"$external_secret"; then
  echo "ExternalSecret must be an ordinary Helm-managed resource, not a hook" >&2
  exit 1
fi

rendered_without_secret="$(
  helm template lifecycle "$chart_dir" \
    --is-upgrade \
    --values "$values_file" \
    --set-string env.DB_USER_PASSWORD.type=kv \
    --set-string env.DB_USER_PASSWORD.value=removed
)"

if grep -q '^kind: ExternalSecret$' <<<"$rendered_without_secret"; then
  echo "ExternalSecret remained in the upgrade manifest after its secret-backed env entry was removed" >&2
  exit 1
fi

echo "ExternalSecret lifecycle rendering passed"
