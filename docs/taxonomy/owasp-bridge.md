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
| MCP04 | Authentication, Authorization & Credential Theft | MCP-T04, MCP-T33, MCP-T34, MCP-T38, MCP-T44 |
| MCP05 | Excessive Scope & Cross-Agent Identity Dilution | MCP-T05, MCP-T17, MCP-T37, MCP-T42, MCP-T43, MCP-T45–T49 |
| MCP06 | Server-Side Request Forgery | MCP-T06 |
| MCP07 | Sensitive Information Disclosure | MCP-T07, MCP-T15, MCP-T41, MCP-T57 |
| MCP08 | Supply Chain | MCP-T08 |
| MCP09 | Insecure Configuration & Infrastructure | MCP-T09, MCP-T50, MCP-T54, MCP-T55, MCP-T58 |
| MCP10 | Denial of Service & Resource Exhaustion | MCP-T10, MCP-T51 |

Resolve a threat ID to its title, lane, and transport in [`lanes.yaml`](lanes.yaml).

## Beyond the Top 10

The hub tracks more than the OWASP MCP Top 10. Nineteen threats
(`MCP-T11`–`T14`, `MCP-T18`–`T32`) carry an `owasp_mcp` value outside
`MCP01`–`MCP10` in `lanes.yaml` — placeholder IDs that mirror the T-number.
They have no direct Top 10 category yet.

Normalizing them into the Top 10 is a deliberate, per-threat security judgment
and is intentionally left as a separate reviewed decision rather than inferred
mechanically. Until then the bridge records them faithfully in the
`beyond_top10` list of [`owasp-bridge.yaml`](owasp-bridge.yaml). Several are
authentication/authorization or delegation threats that would plausibly land in
MCP04 or MCP05; that call belongs to a taxonomy review, not this crosswalk.

## Where this fits

This bridge is a crosswalk within the **attack lens**. See
[`README.md`](README.md) for the four lenses and how they relate.
