#!/usr/bin/env bash
# Verify nullfield's five MCP-aware actions against the policed endpoint.
# Portable: uses the brain-gateway-policed NodePort via the node, or override URL.
#
# Variables:
#   NS    namespace                 (default: camazotz)
#   URL   policed MCP endpoint       (default: http://127.0.0.1:30090/mcp on the node)
set -euo pipefail
NS="${NS:-camazotz}"
URL="${URL:-http://127.0.0.1:30090/mcp}"

call() { # tool timeout
  curl -s -m "${2:-25}" -o /tmp/nf_out -w '%{http_code}' \
    -H 'Content-Type: application/json' -H 'Accept: application/json' -H 'x-principal: ci-deployer' \
    -X POST "$URL" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":{}}}" 2>/dev/null
}
show() { sed -e 's/.\{180\}/&…/' /tmp/nf_out | head -c 200; echo; }

echo ">>> NULLFIELD 5-ACTION MATRIX (MCP-aware PEP)"
echo "[ALLOW ] chain.get_service_manifest  -> HTTP $(call chain.get_service_manifest)"; show
echo "[DENY  ] egress.fetch_url            -> HTTP $(call egress.fetch_url 15)"; show
echo "[SCOPE ] cred_broker.read_credential -> HTTP $(call cred_broker.read_credential)"; show
echo "[HOLD  ] config.update_system_prompt -> HTTP $(call config.update_system_prompt 20)"; show

echo
echo ">>> nullfield audit decisions (proves the action each call took):"
P=$(kubectl -n "$NS" get pod -l app=brain-gateway --field-selector=status.phase=Running -o jsonpath='{.items[-1:].metadata.name}')
kubectl -n "$NS" logs "$P" -c nullfield --tail=40 2>/dev/null \
  | grep -oE '"event_type":"[^"]+","method":"[^"]+","tool":"[^"]+"' | tail -8

cat <<'NOTE'

Expected:
  tool.allowed   chain.get_service_manifest   (ALLOW  — forwarded)
  -32000 denied  egress.fetch_url             (DENY   — blocked before upstream)
  scope.modified cred_broker.read_credential  (SCOPE  — args stripped / response redacted)
  hold.created -> tool.denied (timeout)        (HOLD   — parked for human approval)
BUDGET is enforced per-identity on cost.invoke_llm / rag.query (see policy);
approve a held call with:  POST :31591/admin/holds/<id>/approve  -H 'X-Approver: you'
NOTE
