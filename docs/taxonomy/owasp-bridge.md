# OWASP MCP Top 10 Bridge

A crosswalk between the hub's `MCP-T*` threat vocabulary and the OWASP MCP
Top 10. Use it to translate a finding expressed in OWASP terms into the hub's
lanes/transports/threats model — and back.

The machine-readable form is [`owasp-bridge.yaml`](owasp-bridge.yaml). It is a
faithful projection of the `owasp_mcp` field in [`lanes.yaml`](lanes.yaml) and
is gated by [`../../scripts/check_coherence.py`](../../scripts/check_coherence.py):
the bridge cannot drift from `lanes.yaml` without failing CI. To change a
mapping, edit `lanes.yaml` (the source of truth), not this file.

> Category titles below are the hub's working labels, inferred from the threats
> `lanes.yaml` assigns to each category. Reconcile them against the published
> OWASP MCP Top 10 wording when that is finalized.

## Top 10 → hub threats

| OWASP | Category (working title) | Hub threats |
|-------|--------------------------|-------------|
| MCP01 | Prompt Injection | MCP-T01, MCP-T52, MCP-T53, MCP-T56 |
| MCP02 | Indirect / Tool-Description Injection | MCP-T02, MCP-T35, MCP-T36 |
| MCP03 | Tool Definition Mutation & Content Drift | MCP-T03, MCP-T16, MCP-T39 |
| MCP04 | Authentication, Authorization & Credential Theft | MCP-T04, MCP-T18–T24, MCP-T26, MCP-T28, MCP-T33, MCP-T34, MCP-T38, MCP-T44 |
| MCP05 | Excessive Scope & Cross-Agent Identity Dilution | MCP-T05, MCP-T11, MCP-T17, MCP-T25, MCP-T29, MCP-T32, MCP-T37, MCP-T42, MCP-T43, MCP-T45–T49 |
| MCP06 | Server-Side Request Forgery | MCP-T06 |
| MCP07 | Sensitive Information Disclosure | MCP-T07, MCP-T12, MCP-T15, MCP-T30, MCP-T41, MCP-T57 |
| MCP08 | Supply Chain | MCP-T08 |
| MCP09 | Insecure Configuration & Infrastructure | MCP-T09, MCP-T13, MCP-T14, MCP-T50, MCP-T54, MCP-T55, MCP-T58 |
| MCP10 | Denial of Service & Resource Exhaustion | MCP-T10, MCP-T27, MCP-T31, MCP-T51 |

Resolve a threat ID to its title, lane, and transport in [`lanes.yaml`](lanes.yaml).

## Beyond the Top 10

Normalization is **complete**: every hub threat now carries a canonical
`MCP01`–`MCP10` value in `lanes.yaml`, and the `beyond_top10` list in
[`owasp-bridge.yaml`](owasp-bridge.yaml) is empty. It is kept as an explicit
anchor — a threat added later without a Top 10 category surfaces there and
fails the coherence gate until reconciled.

The nineteen threats that previously sat outside the Top 10 (`MCP-T11`–`T14`,
`MCP-T18`–`T32`) were placed by a per-threat security judgment:

- **MCP04 (Authentication, Authorization & Credential Theft)** absorbed the
  identity and credential cluster — bot-identity theft, cert/OAuth token replay,
  execution-context forgery, sidecar credential tampering, authn downgrade,
  token-lifecycle gaps, and the RBAC/isolation and Teleport privilege-escalation
  bypasses (`MCP-T18`–`T24`, `MCP-T26`, `MCP-T28`).
- **MCP05 (Excessive Scope & Cross-Agent Identity Dilution)** absorbed the
  delegation-chain and scope-boundary threats — delegation abuse and
  depth-driven identity dilution, cross-tenant memory leaks, and the
  policy-authoring defense lab (`MCP-T11`, `MCP-T25`, `MCP-T29`, `MCP-T32`).
- **MCP07 (Sensitive Information Disclosure)** absorbed exfiltration-via-chaining
  and the response-inspection defense lab (`MCP-T12`, `MCP-T30`).
- **MCP09 (Insecure Configuration & Infrastructure)** absorbed webhook
  persistence and audit-log evasion (`MCP-T13`, `MCP-T14`).
- **MCP10 (Denial of Service & Resource Exhaustion)** absorbed LLM cost
  exhaustion/misattribution and the budget-tuning defense lab (`MCP-T27`,
  `MCP-T31`).

Defense-lab threats (`MCP-T29`, `MCP-T30`, `MCP-T31`) are mapped to the category
whose risk they mitigate rather than one they introduce. A few placements are
judgment calls at the boundary between MCP04 and MCP05 (authorization vs. scope)
and MCP07 vs. MCP09 (disclosure vs. configuration); those are documented here so
the reasoning is auditable, not hidden. To revise a mapping, edit `lanes.yaml`.

## Where this fits

This bridge is a crosswalk within the **attack lens**. See
[`README.md`](README.md) for the four lenses and how they relate.
