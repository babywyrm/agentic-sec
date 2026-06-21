# Zero-Trust Agentic Control Plane

A vendor-neutral reference architecture — and a runnable prototype — for securing
a Kubernetes-hosted agentic/MCP workload with **deny-by-default, out-of-band
enforcement**. This is the runnable proof of [`docs/golden-path.md`](../../docs/golden-path.md).

> **Status:** prototype. See [`STATUS.md`](STATUS.md) for the authoritative
> what's-proven / what's-blocked summary across the standalone, Istio-sidecar, and
> Istio-ambient topologies. Intended for a disposable/spare cluster. Generic by
> design — map your own stack onto it; no environment-specific details.
>
> **New here? Start with [`STACK.md`](STACK.md)** — the complete as-built stack
> (all layers A–F), ASCII + Mermaid diagrams, deploy steps, and a one-command
> test runner ([`verify-stack.sh`](verify-stack.sh)). This document is the
> architectural rationale behind it.

---

## The problem it solves

Agentic systems increasingly run as **meshes of MCP servers and sidecars** on
Kubernetes, where agents call tools and tools call other tools. The dangerous
default is that every `tools/call` is forwarded unconditionally, authorization is
left to the LLM (which can be injected/social-engineered), and identity is inferred
from network position. That is the opposite of zero-trust.

This blueprint enforces three principles:

1. **Enforcement is out-of-band and deterministic** — it runs whether or not the
   agent "wants" it to. A guardrail the agent invokes is a guardrail the attacker
   can skip.
2. **Deny by default** — absence of an explicit grant is a denial.
3. **Identity is verified, not asserted** — decisions key off a cryptographic
   workload identity, not a header or an IP.

---

## Layer model

Each tool sits on a distinct layer. Conflating them (e.g. "we have Gatekeeper, so
we're secure") leaves the runtime tool plane wide open.

```
                          ┌─────────────────────────────────────────┐
  client / agent ───────► │  Envoy  (PEP)  :8080                     │
                          │   on every request → ext_authz ──────────┼──► OPA (PDP)
                          │   forwards only if PDP says ALLOW         │     authz.rego
                          └───────────────────┬─────────────────────┘     (deny by default)
                                              │ allowed only
                                              ▼
                                   ┌────────────────────┐
                                   │  MCP server         │  (NetworkPolicy:
                                   │  (the workload)     │   reachable ONLY
                                   └────────────────────┘   from the gateway)
```

| Layer | Question | Component (generic) | This prototype | Atlas domains |
|-------|----------|---------------------|----------------|---------------|
| Identity | *Who is this workload, really?* | SPIFFE/SPIRE or Teleport | Phase 3 (design notes) | F, K |
| Admission (deploy-time) | *Can this pod exist?* | Gatekeeper (OPA) | `40-gatekeeper/` (dryrun) | D, G, J |
| Network | *Can these pods talk, and only as intended?* | NetworkPolicy / mesh mTLS | `30-networkpolicy.yaml` | G |
| **Tool-call authz (runtime)** | *Should THIS `tools/call` run, now, for this principal?* | **PEP + PDP** (Envoy + OPA, or nullfield) | `20-gateway.yaml` + `policy/authz.rego` | B, F, I |
| AI egress | *What may leave to model providers?* | Envoy AI Gateway | future phase | A, E |

**Key distinction:** Gatekeeper/OPA *admission* runs once at pod creation — it is
deploy-time hygiene, not runtime authorization. The per-`tools/call` decision is a
*data-plane* concern handled by the PEP/PDP layer.

---

## PEP / PDP split

- **PEP (Policy Enforcement Point)** — Envoy. Terminates traffic, calls the PDP via
  `ext_authz` on every request (with the MCP JSON-RPC body buffered), and forwards
  only allowed calls. A deny short-circuits with HTTP 403; the backend is never hit.
- **PDP (Policy Decision Point)** — OPA core evaluating [`policy/authz.rego`](policy/authz.rego).
  Deny-by-default; benign protocol methods allowed; `tools/call` gated per-principal.

This split is why the design generalizes: swap the PEP for `nullfield` (MCP-aware)
and keep OPA as a shared PDP so one Rego corpus governs everything — or run OPA as
both. The policy doesn't care which PEP calls it.

---

## Quick start (disposable cluster)

```bash
# Phase 0/1 — the core: PEP + PDP gating a sample MCP workload
./deploy.sh phase1
./demo.sh            # shows allow (benign + granted tools) vs deny (default)

# Phase 2 — admission hygiene (requires Gatekeeper installed; runs in dryrun)
./deploy.sh phase2
kubectl get constraints -A

# tear down
./deploy.sh destroy
```

Expected `demo.sh` output: `initialize`/`tools/list` and granted `tools/call`
return **200**; ungranted tools, unknown principals, and unlisted tools return
**403** — enforced at the gateway before the workload is touched.

---

## What's intentionally deferred

- **Phase 3 identity** — replace the `x-principal` header with a verified SPIFFE
  SVID / Teleport identity, and add on-behalf-of propagation across MCP→MCP hops
  (the confused-deputy / audit-collapse problem). See [`manifests/50-identity/`](manifests/50-identity/README.md).
- **AI egress gateway** — Envoy AI Gateway for model-provider egress (rate/cost
  limits, model allowlists, credential brokering).
- **nullfield as PEP** — the MCP-aware enforcement point delegating decisions to
  this same OPA PDP.

---

## Guaranteeing non-bypassability

The blueprint uses a NetworkPolicy so the gateway is the only path to the MCP
server. **But NetworkPolicy is only as good as the CNI that enforces it** — and
this is a common, dangerous blind spot:

> Plain flannel and some default k3s setups **silently ignore** NetworkPolicy.
> `kubectl apply` succeeds, the object exists, and nothing is actually blocked.
> You get a false sense of security: the PEP looks mandatory but is bypassable
> by calling the workload Service directly.

`demo.sh` includes a **bypass check** that tries to reach the MCP server directly
and tells you whether your cluster actually enforces the policy. Run it on every
cluster — don't assume.

Two ways to get a real guarantee:

1. **Enforcing CNI** — Calico, Cilium, kube-router, Antrea, or Weave. On k3s,
   ensure the embedded network-policy controller is active (don't start with
   `--disable-network-policy`). This keeps the topology in this blueprint.
2. **Sidecar PEP (CNI-independent, strongest)** — run Envoy as a sidecar *inside*
   the MCP pod and bind the app to `127.0.0.1` only. External traffic then has no
   route that skips the proxy, regardless of NetworkPolicy enforcement. This is
   the mesh pattern (and how `nullfield` deploys). Recommended for production
   where you can't guarantee the CNI.

The current manifests use the gateway-deployment topology (clearer for teaching
the PEP/PDP split). For production, move the PEP into the workload pod as a
sidecar so non-bypassability doesn't depend on the network layer.

## Safety on shared clusters

- Everything lives in the `zerotrust` namespace.
- NetworkPolicies are namespace-scoped.
- Gatekeeper constraints bind via `namespaceSelector` to `ztcp.agentic-sec/managed: "true"`
  and start in `enforcementAction: dryrun` — they audit, they do not block, until
  you deliberately promote them to `deny`.

This lets you run the prototype next to other workloads without risking them.

---

## Files

```
zero-trust-control-plane/
├── README.md                      # this document (architecture + rationale)
├── STACK.md                       # the complete as-built stack A–F + diagrams + how to run
├── STATUS.md                      # what's proven / blocked per topology
├── deploy.sh                      # phased apply (phase1 | istio | ambient | phase2)
├── demo.sh / demo-mesh.sh         # allow/deny matrices (standalone / mesh)
├── verify-stack.sh                # one-command test runner across all layers
├── policy/
│   └── authz.rego                 # PDP: deny-by-default tools/call authorization
├── manifests/
│   ├── 00-namespace.yaml · 10-sample-mcp.yaml · 20-gateway.yaml · 30-networkpolicy.yaml
│   ├── 21-istio/                   # sidecar topology (PEP + OPA ext_authz + STRICT mTLS)
│   ├── 22-ambient/                 # ambient topology (ztunnel + waypoint + OPA) — primary
│   ├── 40-gatekeeper/              # admission constraints (dryrun)
│   └── 50-identity/                # Phase 3 identity (design notes)
├── examples/
│   ├── camazotz/                   # real MCP target behind the stack (A, E, F)
│   │   ├── run.sh · verify.sh · authz-camazotz.rego · mesh.yaml
│   │   ├── nullfield-{policy,sidecar}.yaml · nullfield-{deploy,verify}.sh
│   │   ├── drive-flows.py · mcpnuke-validate.sh · mcpnuke-validation.md
│   └── envoy-ai-gateway/           # AI egress layer (D): aigw-ollama.yaml · run.sh · verify.sh
└── observability/                  # see it: kiali.sh · observe.sh · report.sh
```

---

## Related

- [`docs/golden-path.md`](../../docs/golden-path.md) — the production architecture this prototypes
- [`docs/identity-flows.md`](../../docs/identity-flows.md) — the 5 identity lanes (chain = MCP→MCP)
- [`docs/attack-path-atlas.md`](../../docs/attack-path-atlas.md) — threat domains each layer mitigates
- [nullfield](https://github.com/babywyrm/nullfield) — MCP-aware runtime arbiter (drop-in PEP)
