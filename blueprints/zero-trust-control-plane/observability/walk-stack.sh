#!/usr/bin/env bash
# walk-stack.sh — SUPER-VERBOSE walkthrough: for each representative agentic
# flow, show the raw request (method, URL, headers incl. x-principal, JSON-RPC
# body), the raw response (status line, headers, body), and the deciding layer's
# log entry. The educational companion to verify-stack.sh (which is pass/fail).
#
# Usage:
#   NODE=<ip> NS=camazotz ./walk-stack.sh            # run all flows
#   STEP=1 NODE=<ip> ./walk-stack.sh                 # pause between flows
#   ONLY=nf-deny ./walk-stack.sh                     # a single flow by id
#
# Env: NODE (default 127.0.0.1) · NS (camazotz) · ZT_NS (zerotrust)
#      PEP_PORT (30090) · AIGW (http://$NODE) · DECISIONS=1 (show layer log)
set -uo pipefail
KUBECTL="${KUBECTL:-kubectl}"
NODE="${NODE:-127.0.0.1}"; NS="${NS:-camazotz}"; ZT_NS="${ZT_NS:-zerotrust}"
PEP_PORT="${PEP_PORT:-30090}"; AIGW="${AIGW:-http://$NODE}"
PEP="http://$NODE:$PEP_PORT/mcp"
DECISIONS="${DECISIONS:-1}"; STEP="${STEP:-0}"; ONLY="${ONLY:-}"

B=$'\033[1m'; D=$'\033[2m'; G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; C=$'\033[36m'; M=$'\033[35m'; Z=$'\033[0m'

ensure_dbg() {
  [ "$($KUBECTL -n "$NS" get pod dbg -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" ] && return
  $KUBECTL -n "$NS" delete pod dbg --force --grace-period=0 >/dev/null 2>&1
  $KUBECTL -n "$NS" run dbg --image=curlimages/curl:8.10.1 --restart=Never --command -- sleep 7200 >/dev/null 2>&1
  $KUBECTL -n "$NS" wait --for=condition=ready pod/dbg --timeout=60s >/dev/null 2>&1
}

banner() { echo; echo "${B}━━━ $1 ━━━${Z}"; echo "${D}$2${Z}"; }
# colorize curl -v: '>' request (cyan), '<' response (yellow), '*' conn (dim), body as-is
fmt() { sed -E "s/^(> .*)/${C}\1${Z}/; s/^(< HTTP.*)/${Y}${B}\1${Z}/; s/^(< .*)/${Y}\1${Z}/; s/^(\* .*)/${D}\1${Z}/"; }
pause() { [ "${RAN:-0}" = "1" ] && [ "$STEP" = "1" ] && { echo; read -rp "${D}— enter for next flow —${Z}" _; } || true; }

mcp() { local a="${2:-}"; [ -n "$a" ] || a='{}'; printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"%s","arguments":%s}}' "$1" "$a"; }

# raw exchange over the MESH (in-mesh client → waypoint/OPA → ...)
walk_mesh() { # principal tool
  echo "${D}\$ kubectl -n $NS exec dbg -- curl -v -X POST http://brain-gateway:8080/mcp \\
    -H 'x-principal: $1' -H 'Content-Type: application/json' -d '$(mcp "$2")'${Z}"
  $KUBECTL -n "$NS" exec dbg -- curl -sv -m 25 -X POST http://brain-gateway:8080/mcp \
    -H "x-principal: $1" -H 'Content-Type: application/json' -H 'Accept: application/json' \
    -d "$(mcp "$2")" 2>&1 | fmt
}
# raw exchange to the nullfield PEP (policed NodePort)
walk_pep() { # principal tool [args]
  echo "${D}\$ curl -v -X POST $PEP -H 'x-principal: $1' -H 'Content-Type: application/json' -d '$(mcp "$2" "${3:-}")'${Z}"
  curl -sv -m 25 -X POST "$PEP" -H "x-principal: $1" -H 'Content-Type: application/json' \
    -H 'Accept: application/json' -d "$(mcp "$2" "${3:-}")" 2>&1 | fmt
}
# raw exchange to the AI egress gateway (OpenAI /v1)
walk_aigw() { # model
  local body; body="{\"model\":\"$1\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"stream\":false}"
  echo "${D}\$ curl -v -X POST $AIGW/v1/chat/completions -d '$body'${Z}"
  curl -sv -m 60 -X POST "$AIGW/v1/chat/completions" -H 'Content-Type: application/json' -d "$body" 2>&1 | fmt
}

decision() { # layer tool|model
  [ "$DECISIONS" = "1" ] || return 0
  [ "${RAN:-0}" = "1" ] || return 0
  echo "${D}— deciding layer log —${Z}"
  case "$1" in
    nullfield) P=$($KUBECTL -n "$NS" get pod -l app=brain-gateway --field-selector=status.phase=Running -o jsonpath='{.items[-1:].metadata.name}' 2>/dev/null)
      $KUBECTL -n "$NS" logs "$P" -c nullfield --tail=120 2>/dev/null | grep "\"tool\":\"$2\"" | tail -2 | sed "s/^/${M}  [nullfield] ${Z}/" ;;
    opa) P=$($KUBECTL -n "$ZT_NS" get pod -l app=opa-extauthz -o jsonpath='{.items[-1:].metadata.name}' 2>/dev/null)
      $KUBECTL -n "$ZT_NS" logs "$P" --tail=40 2>/dev/null | grep -iE 'decision_id' | tail -1 | cut -c1-110 | sed "s/^/${C}  [opa] ${Z}/" ;;
  esac
}

run() { # id title detail dec_layer dec_target -- fn args...
  local id="$1" title="$2" detail="$3" dl="$4" dt="$5"; shift 5
  [ "${1:-}" = "--" ] && shift
  RAN=0; [ -n "$ONLY" ] && [ "$ONLY" != "$id" ] && return
  RAN=1
  banner "$title" "$detail"
  "$@"
  echo                                   # ensure a newline after curl's body
  [ "$dl" != "-" ] && decision "$dl" "$dt"
  pause
}

ensure_dbg
echo "${B}Walking the zero-trust chain — raw requests at each layer${Z}  ${D}(NODE=$NODE NS=$NS)${Z}"

run opa-allow  "Phase A · OPA waypoint · ALLOW" "ci-deployer is granted code_review.run_checks → forwarded (200)" \
  opa code_review.run_checks -- walk_mesh ci-deployer code_review.run_checks

run opa-deny   "Phase A · OPA waypoint · DENY"  "unknown principal → default-deny at the mesh (403)" \
  - - -- walk_mesh unknown get_status

run nf-allow   "Phase E · nullfield · ALLOW" "benign read on the allowlist → forwarded (200)" \
  - - -- walk_pep ci-deployer chain.get_service_manifest

run nf-deny    "Phase E · nullfield · DENY"  "RCE/SSRF-class tool → JSON-RPC -32000, never reaches the workload" \
  nullfield egress.fetch_url -- walk_pep attacker egress.fetch_url

run nf-scope   "Phase E · nullfield · SCOPE" "credential read → args stripped, secret-shaped values redacted" \
  nullfield cred_broker.read_credential -- walk_pep ci-deployer cred_broker.read_credential '{"api_key":"sk-LEAKME1234567890abcdef"}'

run nf-hold    "Phase E · nullfield · HOLD"  "system-prompt rewrite → parked for approval, then -32005 on timeout" \
  nullfield config.update_system_prompt -- walk_pep attacker config.update_system_prompt

run aigw-allow "Phase D · AI gateway · ALLOW" "allowlisted model qwen3:4b → proxied to the LLM (200)" \
  - - -- walk_aigw qwen3:4b

run aigw-deny  "Phase D · AI gateway · DENY"  "non-allowlisted model → 404 No matching route" \
  - - -- walk_aigw llama3.2:1b

echo; echo "${B}done.${Z} ${D}Tip: STEP=1 to pause between flows; ONLY=<id> for one; mcpnuke --debug for full red-team traffic.${Z}"
