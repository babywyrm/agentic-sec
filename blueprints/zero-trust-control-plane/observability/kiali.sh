#!/usr/bin/env bash
# kiali.sh — install Kiali + Prometheus (Istio addons) if needed, then port-forward
# the Kiali console: the live mesh service graph showing the agentic call path,
# the waypoint in the route, mTLS, and per-edge traffic/health.
#
# Usage:  ./kiali.sh            # install (if needed) + port-forward
#         ./kiali.sh install    # install only
#
# Env:
#   ISTIO_DIR  path to an istio release dir with samples/addons
#              (default: first /opt/istio-* ; override on other hosts)
#   PORT       local port for the Kiali console (default: 20001)
set -euo pipefail
KUBECTL="${KUBECTL:-kubectl}"
PORT="${PORT:-20001}"
ISTIO_DIR="${ISTIO_DIR:-$(ls -d /opt/istio-* 2>/dev/null | head -1 || true)}"
ADDONS_URL="https://raw.githubusercontent.com/istio/istio/release-1.30/samples/addons"

apply_addon() {  # name
  local n="$1"
  if [[ -n "$ISTIO_DIR" && -f "$ISTIO_DIR/samples/addons/$n.yaml" ]]; then
    $KUBECTL apply -f "$ISTIO_DIR/samples/addons/$n.yaml"
  else
    $KUBECTL apply -f "$ADDONS_URL/$n.yaml"
  fi
}

install() {
  if $KUBECTL -n istio-system get deploy kiali >/dev/null 2>&1; then
    echo ">>> Kiali already installed"
  else
    echo ">>> installing Prometheus + Kiali addons"
    apply_addon prometheus
    apply_addon kiali
    $KUBECTL -n istio-system rollout status deploy/kiali --timeout=180s
  fi
}

install
[[ "${1:-}" == "install" ]] && exit 0

echo ">>> Kiali console → http://localhost:${PORT}/kiali  (Ctrl-C to stop)"
echo ">>> tip: Graph → namespace 'camazotz'/'zerotrust', enable 'Security' to see mTLS + the waypoint."
exec $KUBECTL -n istio-system port-forward "svc/kiali" "${PORT}:20001"
