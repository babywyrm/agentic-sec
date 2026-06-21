# Ambient topology (ztunnel + waypoint + OPA ext_authz)

The modern, sidecar-less Istio realization. Instead of injecting a per-pod
istio-proxy, **ambient mode** splits the mesh into two layers:

- **ztunnel** (node-level DaemonSet) — provides L4: mTLS, identity (SPIFFE), and
  the secure overlay. Redirection to ztunnel happens at the node via the istio-cni,
  not per-pod iptables-REDIRECT. This is why ambient can work on hosts where the
  sidecar interception path is broken.
- **waypoint** (per-namespace or per-service proxy) — provides L7: HTTP routing
  and `AuthorizationPolicy` enforcement, including `ext_authz` to OPA. Only traffic
  that needs L7 policy goes through a waypoint.

## Why ambient here

1. Matches the production stack (ztunnel + ambient in use at work).
2. Sidesteps the per-pod sidecar iptables-REDIRECT interception bug seen in the
   sidecar topology (`21-istio/KNOWN-ISSUES.md`) — ztunnel uses node-level
   redirection.
3. No sidecar injection, no privileged istio-init per pod → friendlier to
   restricted PodSecurity.

## Topology

```
  client (ambient ns) ──(ztunnel mTLS)──► waypoint (L7) ──ext_authz──► OPA (PDP)
                                              │  ALLOW / DENY            authz.rego
                                              ▼ allow only
                                          mcp-server (ambient ns)
```

ztunnel gives L4 mTLS + identity for *all* ambient workloads automatically; the
waypoint is what enforces the L7 tool-call decision via OPA.

## Moving parts

1. **Control plane** — Istio installed with the **ambient** profile (adds ztunnel
   DaemonSet + istio-cni). The OPA `extensionProvider` (meshConfig) is the same as
   the sidecar topology (`21-istio/istio-operator.yaml`) and is reused.
2. **`ns-ambient.yaml`** — labels the namespace `istio.io/dataplane-mode=ambient`
   (NOT `istio-injection`). Workloads get L4 via ztunnel with no pod changes.
3. **`waypoint.yaml`** — a waypoint Gateway for the namespace (or mcp-server), which
   handles L7 + ext_authz.
4. **`security.yaml`** — `AuthorizationPolicy` (action: CUSTOM → `opa-ext-authz`)
   targeting the waypoint, plus L4 posture. `PeerAuthentication` is largely implicit
   under ambient (ztunnel enforces mTLS for ambient workloads).

`policy/authz.rego` and the OPA PDP (`21-istio/opa-extauthz.yaml`) are reused
unchanged.

## Apply / test

`../../deploy.sh ambient` then `../../demo-mesh.sh`. Status recorded in the
top-level README and `STATUS.md`.

## Note on identity

L4 identity (SPIFFE SVID via ztunnel) is automatic for ambient workloads. The
waypoint's ext_authz call to OPA carries the request context; Phase 3 swaps the
policy principal from the `x-principal` header to the verified ztunnel identity
(`input.attributes.source.principal`).
