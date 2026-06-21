#!/usr/bin/env bash
# Deploy the Zero-Trust Agentic Control Plane prototype, phase by phase.
#
# The OPA policy ConfigMap is created from policy/authz.rego so the policy has a
# single source of truth in git (not duplicated inside a manifest).
#
# Usage:
#   ./deploy.sh phase1     # namespace + sample MCP + Envoy/OPA gateway (+netpol)
#   ./deploy.sh phase2     # + Gatekeeper constraints (requires Gatekeeper installed)
#   ./deploy.sh status     # show what's running
#   ./deploy.sh destroy    # remove everything (deletes the namespace)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS="zerotrust"
M="$HERE/manifests"

apply_phase1() {
  echo ">>> Phase 0/1: namespace, sample MCP, gateway (Envoy PEP + OPA PDP)"
  kubectl apply -f "$M/00-namespace.yaml"
  # Single source of truth: policy ConfigMap built from the .rego file.
  kubectl create configmap opa-policy \
    --namespace "$NS" \
    --from-file=authz.rego="$HERE/policy/authz.rego" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f "$M/10-sample-mcp.yaml"
  kubectl apply -f "$M/20-gateway.yaml"
  kubectl apply -f "$M/30-networkpolicy.yaml"
  echo ">>> waiting for rollouts..."
  kubectl -n "$NS" rollout status deploy/mcp-server --timeout=120s
  kubectl -n "$NS" rollout status deploy/gateway --timeout=120s
  echo ">>> Phase 1 up. Run ./demo.sh to exercise allow/deny."
}

apply_phase2() {
  echo ">>> Phase 2: Gatekeeper admission constraints (dryrun)"
  if ! kubectl get crd constrainttemplates.templates.gatekeeper.sh >/dev/null 2>&1; then
    echo "!! Gatekeeper not installed. Install it first:" >&2
    echo "   kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.18/deploy/gatekeeper.yaml" >&2
    exit 1
  fi
  kubectl apply -f "$M/40-gatekeeper/templates.yaml"
  sleep 5  # let the constraint CRDs register
  kubectl apply -f "$M/40-gatekeeper/constraints.yaml"
  echo ">>> Constraints applied in dryrun. Check audit violations:"
  echo "    kubectl get constraints -A"
}

find_istioctl() {
  if command -v istioctl >/dev/null 2>&1; then echo istioctl; return; fi
  local c; c=$(ls -d /opt/istio-*/bin/istioctl 2>/dev/null | head -1)
  [[ -n "$c" ]] && echo "$c" || { echo "!! istioctl not found (install Istio first)" >&2; exit 1; }
}

apply_istio() {
  echo ">>> Istio-native topology: sidecar PEP + OPA ext_authz"
  local ISTIOCTL; ISTIOCTL="$(find_istioctl)"
  echo ">>> [1/6] register OPA as a mesh extension provider (control-plane change)"
  "$ISTIOCTL" install -f "$M/21-istio/istio-operator.yaml" -y
  echo ">>> [2/6] enable sidecar injection (+ relax PSA for the istio-init container)"
  kubectl label namespace "$NS" istio-injection=enabled pod-security.kubernetes.io/enforce=privileged --overwrite
  kubectl label namespace "$NS" pod-security.kubernetes.io/warn- >/dev/null 2>&1 || true
  echo ">>> [3/6] policy ConfigMap from authz.rego (single source of truth)"
  kubectl create configmap opa-policy --namespace "$NS" \
    --from-file=authz.rego="$HERE/policy/authz.rego" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo ">>> [4/6] OPA PDP + workload; retire the standalone gateway"
  kubectl apply -f "$M/21-istio/opa-extauthz.yaml"
  kubectl apply -f "$M/10-sample-mcp.yaml"
  kubectl -n "$NS" delete -f "$M/20-gateway.yaml" --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n "$NS" rollout restart deploy/mcp-server
  echo ">>> [5/6] wait for rollouts (sidecars)"
  kubectl -n "$NS" rollout status deploy/opa-extauthz --timeout=120s
  kubectl -n "$NS" rollout status deploy/mcp-server --timeout=120s
  echo ">>> [6/6] mesh security: STRICT mTLS + CUSTOM authz → OPA"
  kubectl apply -f "$M/21-istio/security.yaml"
  echo ">>> Istio-native control plane up. Run ./demo-mesh.sh"
}

apply_ambient() {
  echo ">>> Ambient topology: ztunnel (L4) + waypoint (L7) + OPA ext_authz"
  local ISTIOCTL; ISTIOCTL="$(find_istioctl)"
  echo ">>> [1/7] Gateway API CRDs (required for waypoints)"
  kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1 || \
    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
  echo ">>> [2/7] install Istio ambient profile + OPA extensionProvider + istio-cni (k3s paths)"
  "$ISTIOCTL" install -f "$M/22-ambient/istio-operator.yaml" \
    --set values.cni.cniBinDir=/var/lib/rancher/k3s/data/cni \
    --set values.cni.cniConfDir=/var/lib/rancher/k3s/agent/etc/cni/net.d -y
  echo ">>> [3/7] namespace → ambient data-plane (drop sidecar injection)"
  kubectl label namespace "$NS" istio-injection- >/dev/null 2>&1 || true
  kubectl apply -f "$M/22-ambient/ns-ambient.yaml"
  echo ">>> [4/7] policy ConfigMap + OPA PDP + workload"
  kubectl create configmap opa-policy --namespace "$NS" \
    --from-file=authz.rego="$HERE/policy/authz.rego" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f "$M/21-istio/opa-extauthz.yaml"
  kubectl apply -f "$M/10-sample-mcp.yaml"
  echo ">>> [5/7] restart workloads so they drop sidecars (ambient = no sidecar)"
  kubectl -n "$NS" rollout restart deploy/mcp-server deploy/opa-extauthz
  kubectl -n "$NS" rollout status deploy/opa-extauthz --timeout=120s
  kubectl -n "$NS" rollout status deploy/mcp-server --timeout=120s
  echo ">>> [6/7] waypoint (L7 enforcement point)"
  kubectl apply -f "$M/22-ambient/waypoint.yaml"
  kubectl -n "$NS" rollout status deploy/zerotrust-waypoint-istio-waypoint --timeout=120s 2>/dev/null || true
  echo ">>> [7/7] L7 authz: CUSTOM → OPA at the waypoint"
  kubectl apply -f "$M/22-ambient/security.yaml"
  echo ">>> Ambient control plane up. Run ./demo-mesh.sh"
}

case "${1:-}" in
  phase1) apply_phase1 ;;
  phase2) apply_phase2 ;;
  istio)  apply_istio ;;
  ambient) apply_ambient ;;
  status)
    kubectl -n "$NS" get pods,svc,networkpolicy
    ;;
  destroy)
    kubectl delete namespace "$NS" --ignore-not-found
    echo ">>> (Gatekeeper templates/constraints are cluster-scoped; remove with:"
    echo "    kubectl delete -f $M/40-gatekeeper/constraints.yaml --ignore-not-found"
    echo "    kubectl delete -f $M/40-gatekeeper/templates.yaml --ignore-not-found )"
    ;;
  *)
    echo "Usage: $0 {phase1|istio|ambient|phase2|status|destroy}" >&2
    echo "  phase1   standalone Envoy PEP + OPA PDP (no mesh)" >&2
    echo "  istio    Istio sidecar PEP + OPA ext_authz + STRICT mTLS" >&2
    echo "  ambient  Istio ambient: ztunnel (L4) + waypoint (L7) + OPA ext_authz" >&2
    echo "  phase2   Gatekeeper admission constraints (dryrun)" >&2
    exit 1
    ;;
esac
