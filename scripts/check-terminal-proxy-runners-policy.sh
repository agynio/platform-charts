#!/usr/bin/env bash

set -euo pipefail

chart_dir="${1:-charts/agyn-platform}"
namespace="${2:-platform}"
rendered="$(mktemp)"
policy="$(mktemp)"

cleanup() {
  rm -f "${rendered}" "${policy}"
}
trap cleanup EXIT

helm template agyn-platform "${chart_dir}" --namespace "${namespace}" >"${rendered}"

if grep -q 'Source: agyn-platform/charts/runners/templates/authorizationpolicy.yaml' "${rendered}"; then
  echo "unexpected upstream runners AuthorizationPolicy rendered" >&2
  exit 1
fi

awk '
  /^# Source: agyn-platform\/templates\/runners-authorizationpolicy.yaml$/ {capture=1}
  capture && /^---$/ && seen {exit}
  capture {print; seen=1}
' "${rendered}" >"${policy}"

if [[ ! -s "${policy}" ]]; then
  echo "agyn-platform runners AuthorizationPolicy did not render" >&2
  exit 1
fi

terminal_principal="cluster.local/ns/${namespace}/sa/terminal-proxy"
terminal_count=$(grep -cF "${terminal_principal}" "${policy}" || true)
if [[ "${terminal_count}" != "1" ]]; then
  echo "expected exactly one terminal-proxy principal in runners policy, found ${terminal_count}" >&2
  exit 1
fi

internal_rule=$(awk -v principal="${terminal_principal}" '
  index($0, principal) {capture=1}
  capture && /^    - from:/ && seen {exit}
  capture {print; seen=1}
' "${policy}")

for path in \
  '/agynio.api.runners.v1.RunnersService/ListWorkloads' \
  '/agynio.api.runners.v1.RunnersService/TouchWorkload'; do
  if ! grep -qF "\"${path}\"" <<<"${internal_rule}"; then
    echo "terminal-proxy runners policy rule missing ${path}" >&2
    exit 1
  fi
done

if grep -qF 'request.headers[x-identity-id]' <<<"${internal_rule}"; then
  echo "terminal-proxy internal runners rule unexpectedly requires x-identity-id" >&2
  exit 1
fi

identity_rule=$(awk '
  /request.headers\[x-identity-id\]/ {capture=1}
  capture {print}
' "${policy}")

for path in \
  '/agynio.api.runners.v1.RunnersService/ListWorkloads' \
  '/agynio.api.runners.v1.RunnersService/TouchWorkload'; do
  if grep -qF "\"${path}\"" <<<"${identity_rule}"; then
    echo "caller-identity runners policy rule still contains internal ${path}" >&2
    exit 1
  fi
done

echo "terminal-proxy runners AuthorizationPolicy render check passed"
