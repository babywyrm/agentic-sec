#!/usr/bin/env bash
# Phase F — offensive validation: scan the camazotz target directly vs through
# the nullfield PEP, and report nullfield's runtime deny/allow decisions.
#
# Requires mcpnuke (https://github.com/babywyrm/mcpnuke) on PATH or via uv.
#
# Variables:
#   NODE        node IP exposing the NodePorts        (required, e.g. the node's IP)
#   DIRECT_PORT brain-gateway direct NodePort         (default: 30080)
#   PEP_PORT    nullfield policed NodePort            (default: 30090)
#   NS          camazotz namespace (for audit pull)   (default: camazotz)
#   MCPNUKE     how to invoke mcpnuke                  (default: "uv run mcpnuke")
set -euo pipefail
NODE="${NODE:?set NODE to the node IP exposing the NodePorts}"
DIRECT_PORT="${DIRECT_PORT:-30080}"
PEP_PORT="${PEP_PORT:-30090}"
NS="${NS:-camazotz}"
MCPNUKE="${MCPNUKE:-uv run mcpnuke}"

echo ">>> [1/3] BASELINE scan — direct to brain-gateway (no PEP)"
$MCPNUKE --targets "http://$NODE:$DIRECT_PORT/mcp" --fast --no-k8s --deterministic \
  --json /tmp/f-baseline.json --verbose 2>&1 | grep -E "Findings|CRITICAL|Attack chain" || true

echo
echo ">>> [2/3] PROTECTED scan — through nullfield PEP"
$MCPNUKE --targets "http://$NODE:$PEP_PORT/mcp" --fast --no-k8s --deterministic \
  --json /tmp/f-protected.json --verbose 2>&1 | grep -E "Findings|CRITICAL" || true

echo
echo ">>> [3/3] nullfield RUNTIME decisions during the protected scan (the real signal)"
echo "    (run on the cluster; needs kubectl access to ns/$NS)"
cat <<EOF
kubectl -n $NS logs \$(kubectl -n $NS get pod -l app=brain-gateway \\
  --field-selector=status.phase=Running -o jsonpath='{.items[-1:].metadata.name}') \\
  -c nullfield --tail=2000 | grep -oE '"event_type":"[^"]+"' | sort | uniq -c | sort -rn
EOF
echo
echo ">>> Expected: tool.denied >> tool.allowed (only benign reads forwarded);"
echo "    baseline attack chains are EXECUTABLE, protected invocations are DENIED/HELD."
