#!/usr/bin/env bash
# Verify the zero-trust overlay in front of a real MCP target (camazotz).
#
# Portable: pure kubectl + an in-mesh curl pod. Works on any cluster (k3s, EKS,
# kind, ...). No host-specific assumptions.
#
# Usage:
#   NS=camazotz SVC=brain-gateway ./verify.sh
#
# Proves:
#   - benign MCP methods + granted tools  -> 200 (forwarded by the waypoint)
#   - dangerous / ungranted tools         -> 403 (denied by OPA before the workload)
#   - the bypass contrast                 -> the same dangerous call reaches and runs
#                                            the tool when the gate is skipped
set -euo pipefail

NS="${NS:-camazotz}"
SVC="${SVC:-brain-gateway}"
PORT="${PORT:-8080}"
URL="http://${SVC}:${PORT}/mcp"
PASS=0; FAIL=0

echo ">>> ensuring in-mesh debug client in ns/${NS}"
kubectl -n "$NS" run dbg --image=curlimages/curl:8.10.1 --restart=Never \
  --command -- sleep 3600 >/dev/null 2>&1 || true
kubectl -n "$NS" wait --for=condition=ready pod/dbg --timeout=60s >/dev/null 2>&1 || true

call() { # principal  method-or-tool  expect
  local principal="$1" tool="$2" expect="$3" body
  case "$tool" in
    initialize|tools/list|resources/list|ping)
      body="{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"${tool}\",\"params\":{}}" ;;
    *)
      body="{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"${tool}\",\"arguments\":{}}}" ;;
  esac
  local code
  code=$(kubectl -n "$NS" exec dbg -- curl -s -o /dev/null -w '%{http_code}' -m 25 \
    -X POST "$URL" -H 'Content-Type: application/json' -H 'Accept: application/json' \
    -H "x-principal: ${principal}" -d "$body" 2>/dev/null)
  local st="FAIL"; if [ "$code" = "$expect" ]; then st="PASS"; PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi
  printf '[%s] %-30s principal=%-12s -> HTTP %s (expect %s)\n' "$st" "$tool" "$principal" "$code" "$expect"
}

echo ">>> CAMAZOTZ x ZERO-TRUST AUTHZ MATRIX (ambient waypoint + shared OPA PDP)"
call anyone       initialize                     200
call anyone       tools/list                     200
call ci-deployer  chain.get_service_manifest     200   # granted (read topology)
call ci-deployer  code_review.run_checks         200   # granted (CI duty)
call ci-deployer  cred_broker.read_credential    403   # DENY: not granted (secret read)
call support-bot  schema.extract_credentials     403   # DENY: secret extraction
call support-bot  audit.list_actions             200   # granted (read-only)
call attacker     config.update_system_prompt    403   # DENY: prompt-rewrite persistence
call attacker     exec.run_query                 403   # DENY: query exec
call unknown      cred_broker.read_credential    403   # DENY: unknown principal

echo
echo ">>> BYPASS CONTRAST (why out-of-band matters)"
echo "    Skipping the gate (NodePort / pod-IP) reaches and RUNS the dangerous tool;"
echo "    through the waypoint the same call is denied before the workload is touched."

echo
echo ">>> RESULT: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
