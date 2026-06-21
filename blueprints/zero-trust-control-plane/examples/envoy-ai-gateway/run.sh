#!/usr/bin/env bash
# Phase D — install Envoy Gateway + Envoy AI Gateway and stand up the AI-egress
# control point (model allowlist) in front of a self-hosted, OpenAI-compatible LLM.
#
# Reproducible on any cluster (k3s, EKS, kind). Per-cluster knobs are variables.
#
# Variables:
#   LLM_HOST      upstream LLM host/IP (OpenAI-compatible /v1)  (default: node InternalIP)
#   LLM_PORT      upstream LLM port                              (default: 11434, Ollama)
#   ALLOW_MODEL   the one model id to allowlist                  (default: qwen3:4b)
#   AIGW_VERSION  Envoy AI Gateway + Gateway chart version       (default: v0.0.0-latest)
#                 -> pin to v0.0.0-<commit> for reproducible installs.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LLM_HOST="${LLM_HOST:-}"
LLM_PORT="${LLM_PORT:-11434}"
ALLOW_MODEL="${ALLOW_MODEL:-qwen3:4b}"
AIGW_VERSION="${AIGW_VERSION:-v0.0.0-latest}"

if [ -z "$LLM_HOST" ]; then
  LLM_HOST="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
fi

echo ">>> [1/4] Envoy Gateway (with AI Gateway values)"
helm upgrade -i eg oci://docker.io/envoyproxy/gateway-helm --version "$AIGW_VERSION" \
  -n envoy-gateway-system --create-namespace \
  -f https://raw.githubusercontent.com/envoyproxy/ai-gateway/main/manifests/envoy-gateway-values.yaml
kubectl wait --timeout=180s -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available

echo ">>> [2/4] Envoy AI Gateway CRDs + controller"
helm upgrade -i aieg-crd oci://docker.io/envoyproxy/ai-gateway-crds-helm --version "$AIGW_VERSION" \
  -n envoy-ai-gateway-system --create-namespace
helm upgrade -i aieg oci://docker.io/envoyproxy/ai-gateway-helm --version "$AIGW_VERSION" \
  -n envoy-ai-gateway-system --create-namespace
kubectl wait --timeout=180s -n envoy-ai-gateway-system deployment/ai-gateway-controller --for=condition=Available
kubectl -n envoy-gateway-system rollout restart deploy/envoy-gateway
kubectl -n envoy-gateway-system rollout status deploy/envoy-gateway --timeout=120s

echo ">>> [3/4] apply gateway + allowlist (LLM_HOST=$LLM_HOST:$LLM_PORT ALLOW_MODEL=$ALLOW_MODEL)"
sed -e "s|\${LLM_HOST}|$LLM_HOST|g" \
    -e "s|\${LLM_PORT}|$LLM_PORT|g" \
    -e "s|\${ALLOW_MODEL}|$ALLOW_MODEL|g" \
    "$HERE/aigw-ollama.yaml" | kubectl apply -f -

echo ">>> [4/4] wait for the gateway's Envoy data plane"
sleep 6
kubectl wait pods --timeout=150s -l gateway.envoyproxy.io/owning-gateway-name=aigw \
  -n envoy-gateway-system --for=condition=Ready || true
kubectl get svc -n envoy-gateway-system --selector=gateway.envoyproxy.io/owning-gateway-name=aigw

echo ">>> AI egress gateway up. Verify:  ALLOW_MODEL=$ALLOW_MODEL $HERE/verify.sh"
