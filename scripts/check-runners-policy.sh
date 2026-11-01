#!/usr/bin/env bash
#
# Renders the runners-internal AuthorizationPolicy and evaluates its DENY rules
# for each caller below, on each method in the table, with x-identity-id absent
# and present. The evaluator reads only the rule shapes the template emits and
# fails on any other line, so a new shape has to be taught to it first.

set -euo pipefail

chart_dir="${1:-charts/agyn-platform}"
namespace="${2:-platform}"
rendered="$(mktemp)"
policy="$(mktemp)"
expected="$(mktemp)"

cleanup() {
  rm -f "${rendered}" "${policy}" "${expected}"
}
trap cleanup EXIT

# files refuses to render without an object store; the policy does not read it.
helm template agyn-platform "${chart_dir}" --namespace "${namespace}" \
  --set files.files.s3.endpoint=minio:9000 \
  --set files.files.s3.bucket=agyn-files >"${rendered}"

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

# Service accounts in the release namespace. unlisted stands for any principal
# the policy does not name.
callers="agents-orchestrator terminal-proxy gateway expose notifications chat unlisted"

# The verdict expected for each caller, in the order of ${callers}.
cat >"${expected}" <<'EOF'
CreateWorkload      absent   allow  deny   deny   deny   deny   deny   deny
CreateWorkload      present  allow  deny   deny   deny   deny   deny   deny
GetRunner           absent   allow  deny   deny   deny   deny   deny   deny
GetRunner           present  allow  deny   allow  allow  allow  allow  deny
ListWorkloads       absent   allow  allow  deny   deny   deny   deny   deny
ListWorkloads       present  allow  allow  deny   deny   deny   deny   deny
TouchWorkload       absent   allow  allow  deny   deny   deny   deny   deny
TouchWorkload       present  allow  allow  allow  deny   deny   deny   deny
ReportWorkloadIdle  absent   deny   deny   deny   deny   deny   deny   deny
ReportWorkloadIdle  present  deny   deny   allow  deny   deny   deny   deny
EOF

echo "verdict per caller: ${callers}"
awk -v namespace="${namespace}" -v callers="${callers}" '
  function fail(message) {
    print "runners policy: " message | "cat 1>&2"
    failed = 1
    exit
  }

  # The rendered policy: collect the rules under spec.rules.
  FNR == NR {
    if ($0 == "  action: DENY") {
      deny = 1
      next
    }
    if ($0 == "  rules:") {
      in_rules = 1
      next
    }
    if (!in_rules || $0 ~ /^ *$/) {
      next
    }
    line = $0
    sub(/^ +/, "", line)
    if (line ~ /^- (from|to|when):$/) {
      rules++
      line = substr(line, 3)
    }
    if (line == "from:" || line == "to:" || line == "when:") {
      section = substr(line, 1, length(line) - 1)
      has[rules, section] = 1
      list = ""
    } else if (line == "- source:" && section == "from" && !sources[rules]++) {
      list = ""
    } else if (line == "notPrincipals:" && section == "from") {
      list = "notPrincipals"
    } else if (line == "- operation:" && section == "to" && !operations[rules]++) {
      list = ""
    } else if (line == "paths:" && section == "to") {
      list = "paths"
    } else if (line == "- key: request.headers[x-identity-id]" && section == "when" && !conditions[rules]++) {
      list = ""
    } else if (line == "notValues:" && section == "when") {
      list = "notValues"
    } else if (line == "- \"*\"" && list == "notValues") {
      absent_only[rules] = 1
    } else if (line ~ /^- ".*"$/ && (list == "notPrincipals" || list == "paths")) {
      entries[rules, list, substr(line, 4, length(line) - 4)] = 1
      counts[rules, list]++
    } else {
      fail("unsupported line " FNR ": " $0)
    }
    next
  }

  FNR == 1 {
    if (!deny || !rules) {
      fail("no DENY rules")
    }
    for (r = 1; r <= rules; r++) {
      if (has[r, "when"] && !absent_only[r]) {
        fail("rule " r " has a condition other than x-identity-id absent")
      }
      if ((has[r, "from"] && !counts[r, "notPrincipals"]) || (has[r, "to"] && !counts[r, "paths"])) {
        fail("rule " r " has an empty notPrincipals or paths list")
      }
    }
    caller_count = split(callers, caller, " ")
  }

  # An expected row: method, x-identity-id, then one verdict per caller.
  {
    method = "/agynio.api.runners.v1.RunnersService/" $1
    row = sprintf("%-20s%-9s", $1, $2)
    mismatch = 0
    for (c = 1; c <= caller_count; c++) {
      principal = "cluster.local/ns/" namespace "/sa/" caller[c]
      verdict = "allow"
      for (r = 1; r <= rules; r++) {
        if (has[r, "from"] && ((r, "notPrincipals", principal) in entries)) {
          continue
        }
        if (has[r, "to"] && !((r, "paths", method) in entries)) {
          continue
        }
        if (has[r, "when"] && $2 != "absent") {
          continue
        }
        verdict = "deny"
        break
      }
      row = row sprintf("%-7s", verdict)
      if (verdict != $(c + 2)) {
        mismatch = 1
      }
    }
    sub(/ +$/, "", row)
    if (mismatch) {
      failed = 1
      row = row "  <- expected " $0
    }
    print row
  }

  END {
    exit failed
  }
' "${policy}" "${expected}" || {
  echo "runners AuthorizationPolicy render check failed" >&2
  exit 1
}

echo "runners AuthorizationPolicy render check passed"
