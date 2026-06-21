# Zero-Trust Control Plane — Status

What's proven, what's conditional, and the engineering lessons — per topology.

## Topologies in this blueprint

| # | Topology | PEP | Non-bypass mechanism | Status |
|---|----------|-----|----------------------|--------|
| `20` | Standalone Envoy + OPA | hand-rolled Envoy pod | NetworkPolicy | **Works** (no mesh); NetworkPolicy enforcement is CNI-dependent |
| `21` | Istio sidecar + OPA ext_authz | per-pod istio-proxy | STRICT mTLS | Config proven; inbound interception depends on the host kernel (see caveat) |
| `22` | Istio ambient + waypoint + OPA | ztunnel (L4) + waypoint (L7) | ztunnel mTLS | **Proven end-to-end** on a standard-kernel cluster |

## What is proven

- **Policy** (`policy/authz.rego`) — deny-by-default, per-principal tool-call
  authorization. Reused unchanged across all three topologies.
- **Standalone topology (20)** — full allow/deny matrix green on k3s; OPA decision
  logs; SARIF-style audit. (NetworkPolicy bypass-prevention is CNI-dependent — a
  documented lesson, below.)
- **Istio install + config** — both sidecar and ambient profiles install cleanly;
  OPA `extensionProvider` registered; OPA PDP healthy; `AuthorizationPolicy CUSTOM`
  applied; the OPA **DENY** decision is enforced through the mesh.
- **Identity + mTLS** — verified. In ambient, ztunnel assigns SPIFFE SVIDs
  (`spiffe://cluster.local/ns/<ns>/sa/...`) and initiates HBONE mTLS; in sidecar
  mode the client originates mTLS.
- **Ambient end-to-end (22) — full matrix green** (k3s + flannel, Istio ambient):

  | call | principal | result |
  |------|-----------|--------|
  | `initialize` | anyone | 200 (open method) |
  | `get_status` | `ci-deployer` | 200 (granted) |
  | `scale_deployment` | `ci-deployer` | 200 (granted) |
  | `scale_deployment` | `support-bot` | **403** (wrong principal) |
  | `delete_everything` | `ci-deployer` | **403** (ungranted tool) |
  | `get_status` | `unknown` | **403** (unknown principal) |

- **Non-bypassability** — STRICT mTLS / ztunnel refuses non-mesh callers, and with
  the waypoint set to `waypoint-for: all`, an in-mesh caller hitting the pod IP
  directly (skipping the Service) is **also denied** (403). (With the default
  `waypoint-for: service`, pod-IP-direct calls bypass L7 and return 200.)

## Lessons / caveats

### NetworkPolicy enforcement is CNI-dependent
A `NetworkPolicy` only blocks traffic if the cluster's CNI enforces it. Plain
flannel and some default k3s setups **silently ignore** NetworkPolicy — the
object applies, but nothing is blocked. Always run the bypass check
(`verify-stack.sh` Phase C / `demo.sh`) on the actual cluster. For a hard
guarantee use an enforcing CNI (Calico, Cilium, …) or rely on the mesh waypoint,
which is CNI-independent.

### Istio inbound interception depends on the host kernel
Both mesh topologies require the host to redirect inbound traffic into the mesh
data plane (sidecar `:15006` via iptables-REDIRECT; ambient `:15008` via ztunnel
HBONE). On **some non-standard / custom host kernels** this redirection fails
even though everything in-cluster is correct — the *client* side works (ztunnel
identity + HBONE init), but the *destination* pod's inbound capture returns
`connection refused`. Symptoms to recognize:

- sidecar: client → server pod → `URX/UF connection refused`; the server sidecar
  never sees the request.
- ambient: ztunnel client side works, then `connect to dst :15008 → connection
  refused`.

This is a **host-kernel issue, not a blueprint flaw** (the identical manifests go
green on a standard-kernel cluster). If you hit it: validate on a stock-kernel
node (`kind`/`k3d` or a standard distro kernel), or run an enforcing CNI's own
redirection. `istio-init` / istio-cni chaining and policy/identity/mTLS are all
correct in this state — only the host's netfilter redirection is the problem.

## Two blueprint fixes baked in

Both were found end-to-end and are already applied in `22-ambient/`:

1. **Waypoint enrollment** — the namespace must carry
   `istio.io/use-waypoint: <waypoint>` in addition to
   `istio.io/dataplane-mode: ambient`. Without it, service traffic takes the
   L4-only ztunnel path and **silently bypasses the L7 OPA check** (deny cases
   return 200).
2. **Pod-IP bypass** — set the waypoint to `istio.io/waypoint-for: all` (not
   `service`), so an in-mesh caller can't skip L7 by hitting the pod IP directly.
   Pair with the NetworkPolicy (`30-*`) for L3/L4 bounds.

## Files

- `20-gateway.yaml` + `policy/authz.rego` — standalone (works)
- `21-istio/` — sidecar topology + `KNOWN-ISSUES.md`
- `22-ambient/` — ambient topology (production-aligned)
- `deploy.sh {phase1|istio|ambient|phase2}` · `demo.sh` / `demo-mesh.sh`
