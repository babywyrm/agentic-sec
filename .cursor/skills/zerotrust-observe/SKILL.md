---
name: zerotrust-observe
description: >-
  Drive representative agentic flows through the Zero-Trust Agentic Control Plane
  prototype and visualize what each layer (OPA waypoint, nullfield, Envoy AI
  Gateway, Gatekeeper, NetworkPolicy) delivers. Use when someone wants to demo,
  inspect, or verify the zero-trust blueprint — "show me the flows", "what does
  each layer do", "watch the gating", "is the control plane working" — against a
  running cluster (k3s/EKS/kind) that has the blueprint deployed.
---

# Observe the Zero-Trust Agentic Control Plane

Goal: let anyone *see* what each control-plane layer delivers for agentic MCP
flows. Everything is committed in the blueprint; this skill wires the pieces
into a repeatable drive → observe → report → graph workflow.

## Prerequisites (verify, don't assume)

1. `kubectl` reaches the cluster and the blueprint is deployed:
   `kubectl -n camazotz get pods` (brain-gateway + nullfield sidecar + waypoint),
   `kubectl -n zerotrust get pods` (opa-extauthz), `kubectl -n envoy-ai-gateway-system get pods`.
   If not deployed, see `blueprints/zero-trust-control-plane/deploy.sh ambient`
   and `examples/camazotz/run.sh`, then `examples/camazotz/nullfield-deploy.sh`,
   and `examples/envoy-ai-gateway/run.sh`.
2. The MCP target's LLM backend is reachable (e.g. node-local Ollama). If LLM
   calls fail with 503, only ollama-or-vLLM should hold the GPU — use the
   `brain-swap` tool to switch to a single backend.

Paths below are relative to `blueprints/zero-trust-control-plane/`.

## The workflow

Run from the node (or anywhere with kubectl + curl to the NodePorts/Services).

1. **Graph the mesh** (premier visual) — in one terminal:
   ```bash
   observability/kiali.sh        # installs Kiali+Prometheus if needed, port-forwards
   ```
   Open `http://localhost:20001/kiali` → Graph → namespaces `camazotz`,`zerotrust`;
   enable **Security** to see mTLS + the waypoint in the path.

2. **Stream decisions** — in a second terminal:
   ```bash
   NS=camazotz observability/observe.sh           # live, color-coded
   NS=camazotz observability/observe.sh --since 15m   # recent history
   ```
   One feed across `nullfield` (tool.allowed/denied/scope.modified/hold.created),
   `opa` (decision_ids), `waypoint`, and `ai-gateway` (model + token cost).

3. **Drive flows** — in a third terminal (push representative agentic calls
   through the live cluster and capture each layer's decision):
   ```bash
   NS=camazotz PEP_URL=http://<node>:30090/mcp \
     AIGW_URL=http://<node>/v1/chat/completions \
     python3 examples/camazotz/drive-flows.py > /tmp/flows.json
   ```
   Flows are designed so each is decided by ONE layer: OPA (principal authz),
   nullfield (allow/deny/hold/scope), AI gateway (model allowlist).

4. **Report** — render the capture as a readable table:
   ```bash
   observability/report.sh /tmp/flows.json
   ```
   Expect a healthy run to show `ALLOW=3 DENY=3 HOLD=1 SCOPE=1`.

## Per-layer surfaces (when you want to drill into one piece)

- **OPA / waypoint authz** — `observe.sh` (decision logs); matrix:
  `examples/camazotz/verify.sh`.
- **nullfield** — `observe.sh` audit; the five actions: `examples/camazotz/nullfield-verify.sh`;
  pending human-approval holds: `GET :31591/admin/holds`, approve with
  `POST :31591/admin/holds/<id>/approve -H 'X-Approver: you'`.
- **AI egress** — `examples/envoy-ai-gateway/verify.sh` (allow/deny by model).
- **Gatekeeper** — `kubectl get constraints -A -o wide` (violations/enforcement).
- **NetworkPolicy** — the bypass check in the gateway demo.
- **Offensive before/after** — `examples/camazotz/mcpnuke-validate.sh`
  (direct vs through-PEP; read the runtime deny:allow ratio, not finding count).

## Reporting back

Summarize per layer: what was attempted, what each layer decided, and the net
outcome (reached the workload vs denied/held/scoped). Prefer the `report.sh`
table + the `observe.sh` decision lines as evidence. Don't claim a layer works
without a captured decision for it.
