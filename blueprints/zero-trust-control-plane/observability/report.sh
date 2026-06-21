#!/usr/bin/env bash
# report.sh — render a drive-flows.py capture (flows.json) as a readable table:
# which control-plane layer decided each agentic flow, and how.
#
# Usage:  ./report.sh [flows.json]
set -euo pipefail
F="${1:-flows.json}"
[ -f "$F" ] || { echo "usage: $0 <flows.json>  (run drive-flows.py first)"; exit 1; }

python3 - "$F" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
flows = d.get("flows", [])

def classify(f):
    r = (f.get("reason") or "").lower()
    if "hold" in r: return "HOLD"
    if "scope" in f.get("id","") or "redact" in r or "strip" in r: return "SCOPE"
    return f.get("decision", "?")

C = {"reset":"\033[0m","dim":"\033[2m","grn":"\033[32m","red":"\033[31m","yel":"\033[33m","cyn":"\033[36m","bold":"\033[1m"}
TONE = {"ALLOW":C["grn"], "DENY":C["red"], "HOLD":C["yel"], "SCOPE":C["cyn"]}

print(f"{C['bold']}Zero-trust agentic flows{C['reset']}  {C['dim']}captured {d.get('generated','?')}{C['reset']}\n")
cols = [("Layer (owns)",14), ("Principal",12), ("Target",30), ("Action",7), ("HTTP",6), ("What happened",40)]
def line(cells, color=""):
    out = "  ".join(f"{str(c)[:w].ljust(w)}" for c,(_,w) in zip(cells, cols))
    print(f"{color}{out}{C['reset']}")
line([h for h,_ in cols], C["bold"])
line(["-"*w for _,w in cols], C["dim"])
counts = {}
for f in flows:
    act = classify(f)
    counts[act] = counts.get(act,0)+1
    note = f.get("reason") or f.get("intent","")
    line([f["layer"], f["principal"], f["target"], act, str(f.get("http","")), note], TONE.get(act,""))
print()
summary = "  ".join(f"{TONE.get(k,'')}{k}={v}{C['reset']}" for k,v in sorted(counts.items()))
print(f"{C['bold']}Outcomes:{C['reset']}  {summary}")
print(f"{C['dim']}Benign/granted calls reach the workload; everything else is decided at the layer that owns that concern.{C['reset']}")
PY
