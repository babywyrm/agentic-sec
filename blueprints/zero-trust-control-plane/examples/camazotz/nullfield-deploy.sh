#!/usr/bin/env bash
# Phase E — deploy nullfield as the MCP-aware PEP sidecar in front of the target
# MCP server (camazotz brain-gateway), enforcing the 5-action policy.
#
#   client -> [waypoint + OPA (Phase A)] -> nullfield :9090 -> brain-gateway :8080
#
# nullfield adds HOLD / SCOPE / BUDGET on top of OPA's allow/deny — controls that
# require understanding the MCP call itself. Reproducible on any cluster.
#
# Prereqs: the target deployment (brain-gateway) exists; the nullfield image is
# available to the cluster (build from github.com/babywyrm/nullfield and import:
#   docker build -t nullfield:local -f Dockerfile . && docker save nullfield:local | k3s ctr images import -
# on EKS: build + push to ECR and set IMAGE accordingly).
#
# Variables:
#   NS         target namespace                 (default: camazotz)
#   IMAGE      nullfield image                  (default: nullfield:local)
#   TOOLS_YAML path to the MCP tool registry    (default: camazotz files/nullfield/tools.yaml)
#   POLICY     path to the nullfield policy      (default: ./nullfield-policy.yaml)
#   UPSTREAM   in-pod upstream MCP addr          (default: localhost:8080)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NS="${NS:-camazotz}"
IMAGE="${IMAGE:-nullfield:local}"
POLICY="${POLICY:-$HERE/nullfield-policy.yaml}"
TOOLS_YAML="${TOOLS_YAML:-/opt/camazotz/deploy/helm/camazotz/files/nullfield/tools.yaml}"
UPSTREAM="${UPSTREAM:-localhost:8080}"

echo ">>> [1/4] policy + tool-registry ConfigMaps"
kubectl -n "$NS" create configmap nullfield-tools \
  --from-file=policy.yaml="$POLICY" --from-file=tools.yaml="$TOOLS_YAML" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" create configmap nullfield-config \
  --from-literal=NULLFIELD_LISTEN_ADDR=":9090" \
  --from-literal=NULLFIELD_UPSTREAM_ADDR="$UPSTREAM" \
  --from-literal=NULLFIELD_ADMIN_ADDR=":9091" \
  --from-literal=NULLFIELD_POLICY_PATH="/etc/nullfield/policy.yaml" \
  --from-literal=NULLFIELD_REGISTRY_PATH="/etc/nullfield/tools.yaml" \
  --from-literal=NULLFIELD_AUDIT_LOG_LEVEL="FULL" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ">>> [2/4] inject nullfield sidecar into deploy/brain-gateway"
# distroless:nonroot has a NON-numeric user, so runAsNonRoot needs an explicit
# runAsUser (65532) or the kubelet refuses with CreateContainerConfigError.
kubectl -n "$NS" patch deploy brain-gateway --type strategic -p "$(cat <<JSON
{"spec":{"template":{"spec":{
  "volumes":[{"name":"nullfield-tools","configMap":{"name":"nullfield-tools"}}],
  "containers":[{
    "name":"nullfield","image":"$IMAGE","imagePullPolicy":"IfNotPresent",
    "ports":[{"containerPort":9090,"name":"proxy"},{"containerPort":9091,"name":"admin"}],
    "envFrom":[{"configMapRef":{"name":"nullfield-config"}}],
    "volumeMounts":[{"name":"nullfield-tools","mountPath":"/etc/nullfield","readOnly":true}],
    "readinessProbe":{"httpGet":{"path":"/readyz","port":9091},"initialDelaySeconds":2,"periodSeconds":5},
    "securityContext":{"runAsNonRoot":true,"runAsUser":65532,"allowPrivilegeEscalation":false,"seccompProfile":{"type":"RuntimeDefault"},"capabilities":{"drop":["ALL"]}}
  }]
}}}}
JSON
)"

echo ">>> [3/4] policed endpoint (Service -> nullfield :9090, admin :9091)"
kubectl apply -f "$HERE/nullfield-sidecar.yaml"

echo ">>> [4/4] wait for rollout"
kubectl -n "$NS" rollout status deploy/brain-gateway --timeout=150s
echo ">>> nullfield PEP up. Verify:  NS=$NS $HERE/nullfield-verify.sh"
