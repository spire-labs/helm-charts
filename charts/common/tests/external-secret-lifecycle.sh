#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
chart_dir="$(cd -- "$script_dir/.." && pwd)"
fixtures_dir="$script_dir/fixtures"

render_fixture() {
  helm template lifecycle "$chart_dir" --is-upgrade --values "$fixtures_dir/$1"
}

resource_document() {
  local manifest="$1"
  local resource_name="$2"

  printf '%s\n' "$manifest" |
    awk -v name="  name: \"$resource_name\"" \
      'BEGIN { RS = "---" } /kind: ExternalSecret/ && index($0, name) { print }'
}

assert_resource_count() {
  local manifest="$1"
  local expected="$2"
  local actual

  actual="$(grep -c '^kind: ExternalSecret$' <<<"$manifest" || true)"
  if [[ "$actual" -ne "$expected" ]]; then
    echo "expected $expected ExternalSecrets, rendered $actual" >&2
    exit 1
  fi
}

assert_present() {
  local manifest="$1"
  local resource_name="$2"

  if [[ -z "$(resource_document "$manifest" "$resource_name")" ]]; then
    echo "expected ExternalSecret $resource_name" >&2
    exit 1
  fi
}

assert_absent() {
  local manifest="$1"
  local resource_name="$2"

  if [[ -n "$(resource_document "$manifest" "$resource_name")" ]]; then
    echo "did not expect ExternalSecret $resource_name" >&2
    exit 1
  fi
}

assert_contains() {
  local document="$1"
  local expected="$2"

  if ! grep -Fq -- "$expected" <<<"$document"; then
    echo "expected ExternalSecret document to contain: $expected" >&2
    exit 1
  fi
}

assert_no_hooks() {
  local manifest="$1"
  local external_secrets

  external_secrets="$(
    printf '%s\n' "$manifest" |
      awk 'BEGIN { RS = "---" } /kind: ExternalSecret/ { print }'
  )"
  if grep -q 'helm\.sh/hook' <<<"$external_secrets"; then
    echo "ExternalSecrets must be ordinary Helm-managed resources, not hooks" >&2
    exit 1
  fi
}

initial="$(render_fixture external-secrets-initial.yaml)"
assert_resource_count "$initial" 2
assert_no_hooks "$initial"
assert_present "$initial" lifecycle-common-parameter
assert_present "$initial" lifecycle-common-secret
assert_contains "$(resource_document "$initial" lifecycle-common-parameter)" "name: parameter-store"
assert_contains "$(resource_document "$initial" lifecycle-common-parameter)" "key: /initial/parameter"
assert_contains "$(resource_document "$initial" lifecycle-common-secret)" "name: secrets-manager"
assert_contains "$(resource_document "$initial" lifecycle-common-secret)" "key: initial/secret"

retained="$(render_fixture external-secrets-retained.yaml)"
assert_resource_count "$retained" 2
assert_no_hooks "$retained"
assert_present "$retained" lifecycle-common-parameter
assert_present "$retained" lifecycle-common-secret
assert_contains "$(resource_document "$retained" lifecycle-common-parameter)" "key: /updated/parameter"
assert_contains "$(resource_document "$retained" lifecycle-common-secret)" "key: updated/secret"

renamed="$(render_fixture external-secrets-renamed.yaml)"
assert_resource_count "$renamed" 2
assert_no_hooks "$renamed"
assert_absent "$renamed" lifecycle-common-parameter
assert_present "$renamed" lifecycle-common-parameter-renamed
assert_present "$renamed" lifecycle-common-secret

removed="$(render_fixture external-secrets-removed.yaml)"
assert_resource_count "$removed" 1
assert_no_hooks "$removed"
assert_present "$removed" lifecycle-common-parameter-renamed
assert_absent "$removed" lifecycle-common-secret

echo "ExternalSecret render contract passed"
