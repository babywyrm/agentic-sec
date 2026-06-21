#!/usr/bin/env bash
# Exercise the Istio-native control plane (run after ./deploy.sh istio).
#
# Unlike demo.sh (which port-forwards to a standalone gateway), here the PEP is
# mcp-server's own istio sidecar. With PeerAuthentication STRICT, callers must be
# inside the mesh — so the authz matrix runs from a sidecar-injected client pod,
# and we separately prove a non-mesh caller is rejected.
set -uo pipefail

NS="zerotrust"

echo "================================================================="
echo "  Zero-Trust Control Plane — Istio-native demo"
echo "================================================================="
echo ""
echo "=== authorization matrix (in-mesh client → mcp-server sidecar PEP → OPA) ==="
kubectl -n "$NS" delete pod meshclient --ignore-not-found --force >/dev/null 2>&1
kubectl -n "$NS" run meshclient --image=curlimages/curl:8.10.1 --restart=Never --rm -i --quiet --command -- sh -c '
c() { printf "%-44s principal=%-12s -> HTTP %s (expect %s)\n" "$1" "$2" \
        "$(curl -s -o /dev/null -w "%{http_code}" -m 8 -X POST http://mcp-server/mcp -H "x-principal: $2" -d "$3")" "$4"; }
c "initialize (benign)"         "anyone"      "{\"method\":\"initialize\",\"params\":{}}"                          "200"
c "tools/call get_status"       "ci-deployer" "{\"method\":\"tools/call\",\"params\":{\"name\":\"get_status\"}}"   "200"
c "tools/call scale_deployment" "ci-deployer" "{\"method\":\"tools/call\",\"params\":{\"name\":\"scale_deployment\"}}" "200"
c "tools/call scale_deployment" "support-bot" "{\"method\":\"tools/call\",\"params\":{\"name\":\"scale_deployment\"}}" "403"
c "tools/call delete_everything""ci-deployer" "{\"method\":\"tools/call\",\"params\":{\"name\":\"delete_everything\"}}" "403"
c "tools/call get_status"       "unknown"     "{\"method\":\"tools/call\",\"params\":{\"name\":\"get_status\"}}"   "403"
' 2>&1 | grep -E 'principal='

echo ""
echo "=== non-bypassability (non-mesh client → mcp-server direct; expect blocked) ==="
kubectl -n default delete pod ztcp-bypass --ignore-not-found --force >/dev/null 2>&1
code=$(kubectl -n default run ztcp-bypass --image=curlimages/curl:8.10.1 --restart=Never --rm -i --quiet \
  --command -- curl -s -o /dev/null -w '%{http_code}' -m 6 http://mcp-server.zerotrust.svc.cluster.local/mcp 2>/dev/null)
if [ "$code" = "200" ]; then
  echo "  ✗ WARN: non-mesh caller reached mcp-server (HTTP 200) — STRICT mTLS not enforced?"
else
  echo "  ✓ OK: non-mesh caller blocked (HTTP ${code:-000}) — sidecar requires mTLS."
fi

echo ""
echo ">>> PDP reasoning: kubectl -n $NS logs deploy/opa-extauthz | grep decision"
