#!/usr/bin/env bash
# Verify the AI-egress allowlist: an allowlisted model is proxied to the LLM
# (200), a non-allowlisted model is rejected at the gateway (404) even if the
# backend has it. Portable: uses port-forward, so no LB/Ingress assumptions.
#
# Variables:
#   ALLOW_MODEL   the allowlisted model id            (default: qwen3:4b)
#   DENY_MODEL    a model NOT in the allowlist         (default: llama3.2:1b)
set -euo pipefail

ALLOW_MODEL="${ALLOW_MODEL:-qwen3:4b}"
DENY_MODEL="${DENY_MODEL:-llama3.2:1b}"
LPORT="${LPORT:-18080}"

SVC="$(kubectl get svc -n envoy-gateway-system \
  --selector=gateway.envoyproxy.io/owning-gateway-name=aigw \
  -o jsonpath='{.items[0].metadata.name}')"
[ -n "$SVC" ] || { echo "AI gateway service not found (run ./run.sh first)"; exit 1; }

echo ">>> port-forward svc/$SVC :$LPORT -> :80"
kubectl -n envoy-gateway-system port-forward "svc/$SVC" "$LPORT:80" >/dev/null 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null || true' EXIT
sleep 3

req() { # model expect label
  local model="$1" expect="$2" label="$3" code
  code=$(curl -s -o /tmp/aigw_resp -w '%{http_code}' -m 90 \
    -X POST "http://localhost:$LPORT/v1/chat/completions" -H 'Content-Type: application/json' \
    -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply: GATEWAY OK\"}],\"stream\":false}" 2>/dev/null)
  local st="FAIL"; [ "$code" = "$expect" ] && st="PASS"
  printf '[%s] %-12s model=%-14s -> HTTP %s (expect %s)\n' "$st" "$label" "$model" "$code" "$expect"
}

echo ">>> AI EGRESS ALLOWLIST MATRIX"
req "$ALLOW_MODEL" 200 "ALLOWED"
req "$DENY_MODEL"  404 "DENIED"
echo ">>> (DENIED returns 'No matching route' — egress refused at the control point,"
echo "    not the backend, even though the backend may have the model.)"
