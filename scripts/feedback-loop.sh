#!/usr/bin/env bash
# feedback-loop.sh — Run the full scan → generate → apply → validate cycle
#
# Usage:
#   # Local Docker Compose
#   ./scripts/feedback-loop.sh http://localhost:8080/mcp
#
#   # Kubernetes (through nullfield sidecar)
#   ./scripts/feedback-loop.sh http://192.168.1.85:30080/mcp --k8s camazotz
#
#   # With Claude AI analysis
#   ANTHROPIC_API_KEY=sk-ant-... ./scripts/feedback-loop.sh http://localhost:8080/mcp --claude

set -euo pipefail

TARGET="${1:?Usage: feedback-loop.sh <TARGET_URL> [--k8s NAMESPACE] [--claude]}"
shift

K8S_NS=""
USE_CLAUDE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --k8s) K8S_NS="$2"; shift 2 ;;
    --claude) USE_CLAUDE="--claude --claude-max-tools 5"; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

SCAN_ARGS="--targets $TARGET --fast --no-invoke --verbose"
[ -n "$USE_CLAUDE" ] && SCAN_ARGS="$SCAN_ARGS $USE_CLAUDE"

echo "================================================================"
echo "  FEEDBACK LOOP: scan → generate → apply → validate"
echo "  Target: $TARGET"
echo "  K8s:    ${K8S_NS:-none (local compose)}"
echo "  Claude: ${USE_CLAUDE:-no}"
echo "  Time:   $(date)"
echo "================================================================"

#───────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  STEP 1: Initial Scan                                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"

mcpnuke $SCAN_ARGS \
  --save-baseline /tmp/loop-baseline.json \
  --json /tmp/loop-scan-before.json 2>&1 | tail -15

BEFORE=$(python3 -c "
import json
d = json.load(open('/tmp/loop-scan-before.json'))
f = d['targets'][0]['findings']
c = sum(1 for x in f if x['severity']=='CRITICAL')
h = sum(1 for x in f if x['severity']=='HIGH')
print(f'{len(f)} findings ({c} CRITICAL, {h} HIGH)')
")
echo ""
echo "  Before: $BEFORE"

#───────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  STEP 2: Generate nullfield Policy                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"

mcpnuke --targets $TARGET --fast --no-invoke \
  --generate-policy /tmp/loop-policy.yaml 2>&1 | grep "policy"

echo ""
echo "  Generated policy:"
grep "action:" /tmp/loop-policy.yaml | sed 's/^/    /'
RULES=$(grep -c "action:" /tmp/loop-policy.yaml)
echo "  Total rules: $RULES"

#───────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  STEP 3: Apply Policy                                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"

if [ -n "$K8S_NS" ]; then
  echo "  Applying as K8s CRD in namespace $K8S_NS..."
  kubectl apply -n "$K8S_NS" -f /tmp/loop-policy.yaml 2>&1
  echo ""
  echo "  Waiting 35s for nullfield hot-reload..."
  sleep 35
  echo "  Policy should be active now."
else
  echo "  [Local mode] To apply locally, copy the policy:"
  echo "    cp /tmp/loop-policy.yaml examples/policy.yaml"
  echo "    docker compose restart nullfield"
  echo ""
  echo "  (Skipping apply for local — policy generated at /tmp/loop-policy.yaml)"
fi

#───────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  STEP 4: Re-scan (validate defenses)                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"

mcpnuke $SCAN_ARGS \
  --baseline /tmp/loop-baseline.json \
  --json /tmp/loop-scan-after.json 2>&1 | tail -15

AFTER=$(python3 -c "
import json
d = json.load(open('/tmp/loop-scan-after.json'))
f = d['targets'][0]['findings']
c = sum(1 for x in f if x['severity']=='CRITICAL')
h = sum(1 for x in f if x['severity']=='HIGH')
print(f'{len(f)} findings ({c} CRITICAL, {h} HIGH)')
")
echo ""
echo "  After: $AFTER"

#───────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  RESULTS                                                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Before: $BEFORE"
echo "  After:  $AFTER"
echo "  Policy: $RULES rules generated"
echo ""
echo "  Artifacts:"
echo "    /tmp/loop-baseline.json    — baseline for regression testing"
echo "    /tmp/loop-policy.yaml      — nullfield policy to apply"
echo "    /tmp/loop-scan-before.json — pre-fix scan report"
echo "    /tmp/loop-scan-after.json  — post-fix scan report"
echo ""
echo "  Finished: $(date)"
echo "================================================================"
