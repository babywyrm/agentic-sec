# Observability — see what each layer of the control plane delivers

The control plane is only convincing if you can *watch* it work. This directory
ties together the **native visualization surface of each layer** plus two
aggregate tools, so anyone running the prototype can drive agentic flows and see
exactly where — and how — each call is gated, end to end.

Nothing here is bespoke UI: it uses the tools the stack already ships.

## What visualizes what

| Layer | Native surface | How to reach it |
|-------|----------------|-----------------|
| **Mesh data path** (Istio ambient: ztunnel + waypoint, mTLS) | **Kiali** service graph | `./kiali.sh` → opens the live graph (traffic, mTLS lock, the waypoint in the path) |
| **Tool-call authz** (OPA at the waypoint) | OPA decision logs + waypoint access logs | `./observe.sh` (normalized stream) |
| **MCP-aware PEP** (nullfield) | nullfield **audit events** + **hold admin API** | `./observe.sh`; holds at `:31591/admin/holds` |
| **AI egress** (Envoy AI Gateway) | Envoy access logs (model + token cost) + metrics | `./observe.sh` |
| **Admission** (Gatekeeper) | `kubectl get constraints` + violation events | `kubectl get constraints -A -o wide` |
| **Network** (NetworkPolicy) | CNI enforcement (allow/deny) | `../examples/.../verify` bypass check |
| **The target** (camazotz) | its own **observer** timeline UI | port-forward `brain-gateway` `/_observer/events` |

## The three commands

```bash
# 1) DRIVE — push representative agentic flows through the live cluster,
#    recording each layer's decision (writes flows.json).
NS=camazotz PEP_URL=... AIGW_URL=... python3 ../examples/camazotz/drive-flows.py > flows.json

# 2) REPORT — render that capture as a readable terminal table:
#    "which layer decided each flow, and how".
./report.sh flows.json

# 3) OBSERVE — tail a single normalized, color-coded decision feed across
#    OPA / nullfield / AI gateway while you drive flows (run in a second pane).
./observe.sh            # follow live
./observe.sh --since 5m # recent history

# Plus the mesh picture:
./kiali.sh              # install (if needed) + port-forward Kiali, print the URL
```

### See the RAW requests (super-verbose)

`report.sh` summarizes; `walk-stack.sh` shows the wire. For each flow it prints
the exact request (method, URL, `x-principal` + headers, JSON-RPC body), the raw
response (status, headers, body), and the deciding layer's log line:

```bash
NODE=<node-ip> NS=camazotz ./walk-stack.sh      # all flows, raw
STEP=1 ... ./walk-stack.sh                       # pause between flows
ONLY=nf-scope ... ./walk-stack.sh                # one flow (e.g. watch the
                                                 # SCOPE strip: stripped=[api_key])
```

For full red-team traffic against the target, `mcpnuke --debug` dumps every
probe request/response.

## Typical session

1. `./kiali.sh` in one terminal → open the graph.
2. `./observe.sh` in a second terminal → live decision feed.
3. Run the driver (or `../examples/camazotz/*verify.sh`) in a third → watch the
   calls light up the graph and stream decisions, then `./report.sh` for the
   summary.

Each piece is reproducible on any cluster; per-cluster values (namespace,
endpoints) are arguments/env, never hardcoded.

## For agents

The same workflow is packaged as a Cursor skill at
[`.cursor/skills/zerotrust-observe/`](../../../.cursor/skills/zerotrust-observe/SKILL.md)
— so an agent can drive + observe + report the prototype on request ("show me
the flows", "what does each layer do"). Scripts for humans, skill for agents;
both drive the same committed tooling.
