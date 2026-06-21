#!/usr/bin/env bash
# Stand up the zero-trust overlay in front of a REAL MCP target (camazotz),
# reusing the shared OPA PDP. Reproducible on any cluster (k3s, EKS, kind, ...).
#
# Separation of concerns:
#   - camazotz owns its app manifests (brain-gateway + config/secret).
#   - THIS blueprint contributes the control-plane overlay only:
#       * authz-camazotz.rego  -> the shared OPA PDP corpus (mapped to camazotz tools)
#       * mesh.yaml            -> waypoint + CUSTOM AuthorizationPolicy -> OPA ext_authz
#       * namespace labels     -> ambient data-plane + use-waypoint enrollment
#
# Prereqs: the base ambient control plane is already installed
#   (../../deploy.sh ambient) so istiod/ztunnel/istio-cni + the opa-ext-authz
#   extensionProvider + opa-extauthz PDP exist.
#
# Variables (override as needed):
#   NS            target namespace                       (default: camazotz)
#   OPA_NS        namespace of the shared OPA PDP        (default: zerotrust)
#   WAYPOINT      waypoint Gateway name                  (default: camazotz-waypoint)
#   CAMAZOTZ_DIR  path to a camazotz checkout with kube/ (default: /opt/camazotz)
#   LLM_ENDPOINT  OpenAI/Ollama-compatible base URL      (default: http://<nodeIP>:11434)
#   LLM_MODEL     model name on that endpoint            (default: qwen3:4b)
#   IMAGE         brain-gateway image (build+push for EKS; on k3s: import locally)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NS="${NS:-camazotz}"
OPA_NS="${OPA_NS:-zerotrust}"
WAYPOINT="${WAYPOINT:-camazotz-waypoint}"
CAMAZOTZ_DIR="${CAMAZOTZ_DIR:-/opt/camazotz}"
LLM_ENDPOINT="${LLM_ENDPOINT:-}"
LLM_MODEL="${LLM_MODEL:-qwen3:4b}"

echo ">>> [1/5] deploy the camazotz target (its own manifests)"
kubectl apply -f "$CAMAZOTZ_DIR/kube/namespace.yaml"
kubectl apply -f "$CAMAZOTZ_DIR/kube/configmap.yaml"
kubectl apply -f "$CAMAZOTZ_DIR/kube/secret.yaml"
# Point camazotz's brain at the cluster's LLM. On a bare node, default to the
# node's Ollama; on EKS, pass LLM_ENDPOINT to your in-cluster/remote model svc.
if [ -z "$LLM_ENDPOINT" ]; then
  NODE_IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
  LLM_ENDPOINT="http://${NODE_IP}:11434"
fi
kubectl -n "$NS" patch configmap camazotz-config \
  -p "{\"data\":{\"BRAIN_PROVIDER\":\"local\",\"OLLAMA_HOST\":\"${LLM_ENDPOINT}\",\"CAMAZOTZ_OLLAMA_MODEL\":\"${LLM_MODEL}\"}}"
kubectl apply -f "$CAMAZOTZ_DIR/kube/brain-gateway.yaml"

echo ">>> [2/5] load the camazotz-mapped policy into the SHARED OPA PDP (ns/${OPA_NS})"
kubectl create configmap opa-policy --namespace "$OPA_NS" \
  --from-file=authz.rego="$HERE/authz-camazotz.rego" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$OPA_NS" rollout restart deploy/opa-extauthz

echo ">>> [3/5] enroll the target namespace in ambient + the waypoint"
kubectl label namespace "$NS" \
  istio.io/dataplane-mode=ambient \
  istio.io/use-waypoint="$WAYPOINT" \
  pod-security.kubernetes.io/enforce=baseline --overwrite

echo ">>> [4/5] apply the overlay: waypoint + CUSTOM authz -> OPA ext_authz"
kubectl apply -f "$HERE/mesh.yaml"

echo ">>> [5/5] restart the target into the mesh + wait"
kubectl -n "$NS" rollout restart deploy/brain-gateway
kubectl -n "$OPA_NS" rollout status deploy/opa-extauthz --timeout=120s
kubectl -n "$NS" rollout status deploy/brain-gateway --timeout=120s

echo ">>> overlay up. Verify:  NS=${NS} ${HERE}/verify.sh"
