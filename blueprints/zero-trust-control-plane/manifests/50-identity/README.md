# Phase 3 — Workload Identity (replace the header-based principal)

Phase 1 asserts the principal via an `x-principal` header. That is spoofable and
exists only to prove the policy path. Phase 3 replaces it with a **cryptographically
verifiable workload identity** so the PDP keys decisions off something the caller
cannot forge.

## Why this is the load-bearing phase

Every layer above identity is guessing if it can't answer *"who is this workload,
really?"*. Network position is not identity. A header is not identity. An SVID is.

## Two paths

### A. SPIFFE / SPIRE (vendor-neutral, recommended for the generic blueprint)

- SPIRE server issues SVIDs; SPIRE agent attests workloads via node + workload
  attestation (k8s service-account, pod selectors).
- Envoy receives the SVID over the SPIFFE Workload API and presents it on mTLS.
- The peer SVID (`spiffe://<trust-domain>/ns/zerotrust/sa/<sa>`) becomes the
  `principal` in `authz.rego` — replacing `input.attributes.request.http.headers["x-principal"]`
  with `input.attributes.source.principal` (the validated mTLS identity Envoy passes
  to OPA).

Policy change (illustrative):

```rego
# Phase 1
principal := input.attributes.request.http.headers["x-principal"]

# Phase 3 — identity comes from the verified mTLS peer SVID, not a header
principal := input.attributes.source.principal
```

### B. Teleport Machine ID (if you already run Teleport)

A cluster with Teleport + `tbot` already issues short-lived, attested machine
identities. Bind the workload's Teleport identity into the mesh and map it to the
`principal`. This reuses existing PKI instead of standing up SPIRE.

## Identity propagation across MCP→MCP hops (the hard problem)

When MCP A calls MCP B, the *original* principal must propagate — not get replaced
by A's identity at each hop, or you get confused-deputy and audit collapse
(Atlas Lane 4, MCP-T03/T13). Use a token-exchange / on-behalf-of pattern:

- A presents its own SVID **plus** an on-behalf-of assertion carrying the upstream
  principal.
- The PDP authorizes B's tool against the *original* principal AND records the full
  delegation chain (depth-limited — deny past a configured `maxDepth`).

This phase is intentionally left as design notes; implement after Phases 0–2 are
solid on the prototype.
