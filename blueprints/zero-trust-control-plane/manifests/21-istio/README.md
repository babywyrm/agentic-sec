# Istio-native topology (sidecar PEP + OPA ext_authz)

The production-grade realization of the control plane. Where the Phase-1
standalone gateway (`20-gateway.yaml`) hand-rolls one Envoy in front of the
workload, this variant uses the **service mesh**: every workload's own injected
istio-proxy sidecar is the PEP, mTLS is automatic and mandatory, and the
tool-call decision is delegated to OPA as a mesh external-authorization provider.

## Why this is better than the standalone gateway

- **Non-bypassable by mTLS, not NetworkPolicy.** `PeerAuthentication: STRICT`
  makes every sidecar reject non-mesh/plaintext traffic. This holds even when the
  CNI does not enforce NetworkPolicy (the gap found on k3s/flannel).
- **No double-proxy.** Putting a hand-rolled Envoy in a pod that *also* gets an
  istio sidecar creates two Envoys fighting over the upstream hop (observed as
  503s on the allow path). The mesh sidecar IS the proxy — one clean data path.
- **Same policy.** `policy/authz.rego` is reused verbatim. The mesh sidecar sends
  the same Envoy ext_authz `CheckRequest` (incl. the buffered MCP JSON-RPC body)
  that our standalone Envoy did.

## Topology

```
  in-mesh client ──(mTLS)──► mcp-server sidecar (PEP)
                                  │  AuthorizationPolicy action: CUSTOM
                                  ▼  ext_authz (gRPC, body included)
                              opa-extauthz (PDP)  ── policy/authz.rego
                                  │  ALLOW / DENY
                                  ▼ allow only
                              mcp-server app
```

## The three moving parts

1. **`istio-operator.yaml`** — registers OPA as a mesh `extensionProvider`
   (`envoyExtAuthzGrpc`) with `includeRequestBodyInCheck` so the sidecar forwards
   the MCP body to OPA. Applied with `istioctl install -f`. *(Control-plane change.)*
2. **`opa-extauthz.yaml`** — OPA Deployment + Service (the PDP), gRPC ext_authz on
   `:9191`, policy from the `opa-policy` ConfigMap. Port is `appProtocol: grpc`.
3. **`security.yaml`** — `PeerAuthentication: STRICT` + `AuthorizationPolicy`
   (action: CUSTOM, provider `opa-ext-authz`) selecting `app: mcp-server`.

The standalone `20-gateway.yaml` is **retired** in this topology (kept in the repo
as the no-mesh teaching variant).

## Identity note

This still keys authorization off the `x-principal` header (Phase 1 model). In the
mesh, the verified caller identity is also available to OPA as
`input.attributes.source.principal` (the peer mTLS SVID). Phase 3 swaps the policy
to use the SVID so the principal cannot be spoofed by a header. The mesh already
authenticates *who* the caller is (mTLS); the SVID swap makes authorization use it.

## Apply / test

See `../../deploy.sh istio` and `../../demo-mesh.sh`.

## Status / known issues

**Verified:** Istio install, sidecar injection, `PeerAuthentication: STRICT`
non-bypassability (non-mesh callers refused), OPA ext_authz wiring + enforced
DENY decisions.

**Blocked on the original test host:** the legitimate in-mesh data path to the
workload (sidecar inbound → app) 503s due to a **host-level iptables REDIRECT
interception bug** on a custom kernel — independent of mTLS and policy (proven by
bisection). See [`KNOWN-ISSUES.md`](KNOWN-ISSUES.md) for the full diagnostic trail
and resolutions (validate on a stock-kernel cluster; or use ambient/istio-cni).
