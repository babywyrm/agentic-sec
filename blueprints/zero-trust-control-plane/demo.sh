#!/usr/bin/env bash
# Exercise the gateway: show that the PDP allows benign methods + granted tools
# and denies everything else (default deny). Run after ./deploy.sh phase1.
#
# Port-forwards the gateway to localhost:8080, then fires JSON-RPC requests.
set -uo pipefail

NS="zerotrust"
PORT="${PORT:-8080}"

echo ">>> port-forwarding gateway → localhost:$PORT"
kubectl -n "$NS" port-forward svc/gateway "$PORT:8080" >/dev/null 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null' EXIT
sleep 3

call() {  # call <label> <principal> <json-body> <expected>
  local label="$1" principal="$2" body="$3" expected="$4"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "http://localhost:$PORT/mcp" \
    -H "Content-Type: application/json" \
    -H "x-principal: $principal" \
    -d "$body")
  printf '%-46s principal=%-18s → HTTP %s  (expected %s)\n' "$label" "$principal" "$code" "$expected"
}

echo ""
echo "=== Zero-Trust Control Plane — authorization demo ==="
echo ""

# Benign protocol methods: allowed regardless of principal.
call "initialize (benign)"            "anyone"     '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'                                  "200"
call "tools/list (benign)"            "anyone"     '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'                                  "200"

# Granted tool calls: allowed for the right principal.
call "tools/call get_status"          "ci-deployer" '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_status"}}'             "200"
call "tools/call scale_deployment"    "ci-deployer" '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"scale_deployment"}}'       "200"

# Denials: principal lacks the grant, or no principal at all.
call "tools/call scale_deployment"    "support-bot" '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"scale_deployment"}}'       "403"
call "tools/call delete_everything"   "ci-deployer" '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"delete_everything"}}'      "403"
call "tools/call get_status (no id)"  "unknown"     '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_status"}}'             "403"

echo ""
echo "=== NetworkPolicy enforcement check (can the gateway be bypassed?) ==="
# Try to reach the MCP server DIRECTLY, skipping the gateway. If the cluster
# enforces NetworkPolicy this is blocked (the only allowed source is the gateway).
# If it succeeds, your CNI is NOT enforcing NetworkPolicy and the PEP is bypassable.
kubectl -n default delete pod ztcp-bypass --ignore-not-found --force >/dev/null 2>&1
direct=$(kubectl -n default run ztcp-bypass --image=curlimages/curl:8.10.1 --restart=Never --rm -i --quiet \
  --command -- curl -s -o /dev/null -w '%{http_code}' -m 6 \
  http://mcp-server.zerotrust.svc.cluster.local/ 2>/dev/null)
if [ "$direct" = "200" ]; then
  echo "  ✗ WARN: direct access to mcp-server returned 200 — NetworkPolicy is NOT enforced."
  echo "         The gateway can be bypassed on this cluster. See README →"
  echo "         'Guaranteeing non-bypassability' (use an enforcing CNI or sidecar PEP)."
else
  echo "  ✓ OK: direct access blocked (got '${direct:-no-response}') — gateway is the only path."
fi

echo ""
echo ">>> Inspect the PDP's reasoning:"
echo "    kubectl -n $NS logs deploy/gateway -c opa | grep decision"
