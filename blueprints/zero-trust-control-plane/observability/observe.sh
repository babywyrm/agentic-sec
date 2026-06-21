#!/usr/bin/env bash
# observe.sh — one normalized, color-coded decision feed across the runtime
# control-plane layers (nullfield · OPA/waypoint · AI gateway). Run it in a
# second terminal while you drive flows and watch each call get gated.
#
# Usage:
#   ./observe.sh                 # follow live (tail -f)
#   ./observe.sh --since 10m     # recent history, then exit
#
# Env (per-cluster; all have sane defaults):
#   NS      target/MCP namespace (nullfield + waypoint)   default: camazotz
#   ZT_NS   namespace of the shared OPA PDP               default: zerotrust
#   EGW_NS  Envoy Gateway namespace (AI gateway dataplane) default: envoy-gateway-system
set -uo pipefail

NS="${NS:-camazotz}"
ZT_NS="${ZT_NS:-zerotrust}"
EGW_NS="${EGW_NS:-envoy-gateway-system}"
KUBECTL="${KUBECTL:-kubectl}"

MODE="follow"; SINCE_ARGS=(-f --tail=0)
if [[ "${1:-}" == "--since" ]]; then MODE="history"; SINCE_ARGS=(--since "${2:-10m}"); fi

C_NF=$'\033[35m'; C_OPA=$'\033[36m'; C_AIGW=$'\033[33m'; C_WP=$'\033[34m'; C_RST=$'\033[0m'; C_DIM=$'\033[2m'

pod() { $KUBECTL -n "$1" get pod -l "$2" --field-selector=status.phase=Running -o jsonpath='{.items[-1:].metadata.name}' 2>/dev/null; }

NF_POD=$(pod "$NS" "app=brain-gateway")
OPA_POD=$(pod "$ZT_NS" "app=opa-extauthz")
WP_POD=$(pod "$NS" "gateway.networking.k8s.io/gateway-name=camazotz-waypoint")
AIGW_POD=$(pod "$EGW_NS" "gateway.envoyproxy.io/owning-gateway-name=aigw")

pids=()
cleanup() { for p in "${pids[@]:-}"; do kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT INT TERM

echo "${C_DIM}observe: nullfield=${NF_POD:-none} opa=${OPA_POD:-none} waypoint=${WP_POD:-none} aigw=${AIGW_POD:-none}  (mode: $MODE)${C_RST}"
echo "${C_DIM}---------------------------------------------------------------------------${C_RST}"

# nullfield audit — the richest source (allow/deny/hold/scope per tool).
if [[ -n "$NF_POD" ]]; then
  ( $KUBECTL -n "$NS" logs "${SINCE_ARGS[@]}" "$NF_POD" -c nullfield 2>/dev/null \
    | grep --line-buffered '"event_type"' \
    | while IFS= read -r l; do
        et=$(sed -n 's/.*"event_type":"\([^"]*\)".*/\1/p' <<<"$l")
        tool=$(sed -n 's/.*"tool":"\([^"]*\)".*/\1/p' <<<"$l")
        printf '%s[nullfield ]%s %-18s %s\n' "$C_NF" "$C_RST" "$et" "$tool"
      done ) & pids+=($!)
fi

# OPA PDP decisions (opa-envoy plugin; visible when decision logging is on).
if [[ -n "$OPA_POD" ]]; then
  ( $KUBECTL -n "$ZT_NS" logs "${SINCE_ARGS[@]}" "$OPA_POD" 2>/dev/null \
    | grep --line-buffered -iE 'decision|"allow"|denied|tools/call' \
    | while IFS= read -r l; do printf '%s[opa      ]%s %s\n' "$C_OPA" "$C_RST" "${l:0:120}"; done ) & pids+=($!)
fi

# Waypoint (Envoy) access logs — request + ext_authz result through the mesh.
if [[ -n "$WP_POD" ]]; then
  ( $KUBECTL -n "$NS" logs "${SINCE_ARGS[@]}" "$WP_POD" 2>/dev/null \
    | grep --line-buffered -E 'mcp|HTTP|POST' \
    | while IFS= read -r l; do printf '%s[waypoint ]%s %s\n' "$C_WP" "$C_RST" "${l:0:120}"; done ) & pids+=($!)
fi

# AI gateway (Envoy) access logs — model + token cost on egress.
if [[ -n "$AIGW_POD" ]]; then
  ( $KUBECTL -n "$EGW_NS" logs "${SINCE_ARGS[@]}" "$AIGW_POD" 2>/dev/null \
    | grep --line-buffered -iE 'model|chat/completions|x-ai-eg' \
    | while IFS= read -r l; do printf '%s[ai-gateway]%s %s\n' "$C_AIGW" "$C_RST" "${l:0:120}"; done ) & pids+=($!)
fi

[[ ${#pids[@]} -eq 0 ]] && { echo "no control-plane pods found in ns/$NS,$ZT_NS,$EGW_NS"; exit 1; }
wait
