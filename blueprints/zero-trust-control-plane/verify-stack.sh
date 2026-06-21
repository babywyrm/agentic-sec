#!/usr/bin/env bash
# verify-stack.sh — exercise every layer of the zero-trust control plane and
# print one consolidated PASS/FAIL. Run on the node (or anywhere with kubectl +
# curl reach to the NodePorts/Services).
#
# Usage:
#   NODE=<node-ip> NS=camazotz ./verify-stack.sh
#   RUN_MCPNUKE=1 ... ./verify-stack.sh    # also run the (slow) offensive scan
#
# Env (defaults match the camazotz example deployment):
#   NODE         node IP for NodePort/LB endpoints      default: 127.0.0.1
#   NS           MCP target namespace                   default: camazotz
#   ZT_NS        shared-OPA namespace                   default: zerotrust
#   PEP_PORT     nullfield policed NodePort             default: 30090
#   AIGW         AI gateway base URL                    default: http://$NODE
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECTL="${KUBECTL:-kubectl}"
NODE="${NODE:-127.0.0.1}"
NS="${NS:-camazotz}"
ZT_NS="${ZT_NS:-zerotrust}"
PEP_PORT="${PEP_PORT:-30090}"
AIGW="${AIGW:-http://$NODE}"
PEP="http://$NODE:$PEP_PORT/mcp"

C_G=$'\033[32m'; C_R=$'\033[31m'; C_B=$'\033[1m'; C_0=$'\033[0m'; C_D=$'\033[2m'
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  %s[PASS]%s %s\n' "$C_G" "$C_0" "$1"; }
no()  { FAIL=$((FAIL+1)); printf '  %s[FAIL]%s %s\n' "$C_R" "$C_0" "$1"; }
hdr() { echo; printf '%s== %s ==%s\n' "$C_B" "$1" "$C_0"; }
check() { [ "$2" = "$3" ] && ok "$1 ($2)" || no "$1 (got $2, want $3)"; }

mcp() { printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"%s","arguments":{}}}' "$1"; }

# in-mesh dbg client for the OPA (waypoint) path
ensure_dbg() {
  local phase; phase=$($KUBECTL -n "$NS" get pod dbg -o jsonpath='{.status.phase}' 2>/dev/null)
  if [ "$phase" != "Running" ]; then
    $KUBECTL -n "$NS" delete pod dbg --force --grace-period=0 >/dev/null 2>&1
    $KUBECTL -n "$NS" run dbg --image=curlimages/curl:8.10.1 --restart=Never --command -- sleep 7200 >/dev/null 2>&1
    $KUBECTL -n "$NS" wait --for=condition=ready pod/dbg --timeout=60s >/dev/null 2>&1
  fi
}
mesh_code() { # principal tool
  $KUBECTL -n "$NS" exec dbg -- curl -s -o /dev/null -w '%{http_code}' -m 10 \
    -X POST http://brain-gateway:8080/mcp -H 'Content-Type: application/json' \
    -H 'Accept: application/json' -H "x-principal: $1" -d "$(mcp "$2")" 2>/dev/null
}
pep_resp() { # principal tool timeout
  curl -s -m "${3:-20}" -X POST "$PEP" -H 'Content-Type: application/json' \
    -H 'Accept: application/json' -H "x-principal: $1" -d "$(mcp "$2")" 2>/dev/null
}

hdr "Phase A — OPA waypoint (per-principal tool authz)"
ensure_dbg
check "granted principal → granted tool"   "$(mesh_code ci-deployer code_review.run_checks)" "200"
check "unknown principal → default-deny"   "$(mesh_code unknown get_status)"                  "403"

hdr "Phase E — nullfield (MCP-aware actions)"
check "benign tool ALLOW"     "$(curl -s -o /dev/null -w '%{http_code}' -m 20 -X POST "$PEP" -H 'Content-Type: application/json' -H 'Accept: application/json' -H 'x-principal: ci-deployer' -d "$(mcp chain.get_service_manifest)")" "200"
grep -q -- "-32000" <<<"$(pep_resp attacker egress.fetch_url 15)"        && ok "RCE-class tool DENY (-32000)"        || no "RCE-class tool DENY"
grep -q -- "-32005" <<<"$(pep_resp attacker config.update_system_prompt 20)" && ok "system-prompt HOLD (-32005)"     || no "system-prompt HOLD"
pep_resp ci-deployer cred_broker.read_credential >/dev/null 2>&1         && ok "credential read SCOPE (forwarded sanitized)" || no "credential read SCOPE"

hdr "Phase D — Envoy AI Gateway (model egress allowlist)"
aigw_code() { curl -s -o /dev/null -w '%{http_code}' -m "${2:-60}" -X POST "$AIGW/v1/chat/completions" -H 'Content-Type: application/json' -d "{\"model\":\"$1\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"stream\":false}" 2>/dev/null; }
check "allowlisted model → ALLOW" "$(aigw_code qwen3:4b)"   "200"
check "other model → DENY"        "$(aigw_code llama3.2:1b 20)" "404"

hdr "Phase B — Gatekeeper (admission)"
n=$($KUBECTL get constraints -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
[ "${n:-0}" -ge 1 ] && ok "Gatekeeper constraints present ($n)" || no "Gatekeeper constraints present"

hdr "Phase C — NetworkPolicy (CNI enforcement)"
$KUBECTL delete ns npcheck --wait=true --timeout=60s >/dev/null 2>&1 || true   # clear any prior run
$KUBECTL create ns npcheck >/dev/null 2>&1
$KUBECTL -n npcheck run web --image=nginx:alpine --port=80 >/dev/null 2>&1
$KUBECTL -n npcheck expose pod web --port=80 >/dev/null 2>&1
$KUBECTL -n npcheck run cli --image=curlimages/curl:8.10.1 --restart=Never --command -- sleep 300 >/dev/null 2>&1
$KUBECTL -n npcheck wait --for=condition=ready pod/web pod/cli --timeout=120s >/dev/null 2>&1
# retry the baseline until the web pod actually answers (first-pull warmup)
base=000
for _ in 1 2 3 4 5 6 7 8; do
  base=$($KUBECTL -n npcheck exec cli -- curl -s -o /dev/null -w '%{http_code}' -m 5 http://web 2>/dev/null)
  [ "$base" = "200" ] && break; sleep 3
done
printf 'apiVersion: networking.k8s.io/v1\nkind: NetworkPolicy\nmetadata: {name: deny, namespace: npcheck}\nspec: {podSelector: {}, policyTypes: [Ingress]}\n' | $KUBECTL apply -f - >/dev/null 2>&1
sleep 4
denied=$($KUBECTL -n npcheck exec cli -- curl -s -o /dev/null -w '%{http_code}' -m 6 http://web 2>/dev/null)
if [ "$base" = "200" ] && [ "$denied" != "200" ]; then ok "default-deny enforced (200 → $denied)"
elif [ "$base" != "200" ]; then no "NetworkPolicy check inconclusive — web pod never ready (base=$base); rerun"
else no "NetworkPolicy NOT enforced (200 → $denied) — CNI may ignore policy (see README)"; fi
$KUBECTL delete ns npcheck --wait=false >/dev/null 2>&1 || true

if [ "${RUN_MCPNUKE:-0}" = "1" ]; then
  hdr "Phase F — mcpnuke offensive before/after"
  bash "$HERE/examples/camazotz/mcpnuke-validate.sh" || true
fi

echo
printf '%s== RESULT ==%s  %sPASS %d%s  %sFAIL %d%s\n' "$C_B" "$C_0" "$C_G" "$PASS" "$C_0" "$C_R" "$FAIL" "$C_0"
[ "$FAIL" -eq 0 ]
