# Roadmap & Future Work

> **Status:** Living document · **Scope:** the agentic-sec hub and its five tools
> (camazotz, nullfield, mcpnuke, stoneburner, skillseraph)

This document tracks where the ecosystem is mature, where it is thin, and what
should be built next to **unify the shared vocabulary**, **mature the tools**, and
**harden the tools themselves**. It is the planning companion to
[`ecosystem.md`](ecosystem.md) (architecture) and
[`feedback-loop.md`](feedback-loop.md) (the scan → enforce → validate loop).

---

## Maturity at a glance

| Area | State | Notes |
|---|---|---|
| Vulnerable target (camazotz) | **Strong** | 52 labs, 5 lanes × 5 transports, full OWASP MCP Top 10 |
| Policy arbiter (nullfield) | **Strong** | 5 actions, sidecar/gateway/webhook, 139-tool camazotz policy |
| Scanner (mcpnuke) | **Strong** | static + behavioral + AI-assisted, emits nullfield policy |
| Benchmarking + eval (stoneburner) | **Strong** | provider benchmarking, adversarial/redblue suites, security-architecture review (`archreview`), API server mode (`atomics server`) |
| Config scanner (skillseraph) | **Strong** | scans `AGENTS.md`/`SKILL.md`/rules/hooks/MCP configs across 11 platforms; covers Attack Path Atlas Domain J |
| Shared taxonomy (MCP-T threats, lanes, transports) | **Strong** | canonical in `lanes.yaml`; surface lens (`surfaces.yaml`) and OWASP MCP Top 10 bridge (`owasp-bridge.yaml`) now first-class and CI-gated; 19 threats await Top 10 normalization |
| Taxonomy lenses (identity / attack / surface / tool) | **Strong** | four-lens model documented in `docs/taxonomy/` with a machine-readable surface inventory |
| Defensive operations (detection, IR, purple team) | **Thin** | scattered across campaigns/walkthroughs; no consolidated catalog |
| Tool security posture (supply chain, authz, secrets) | **Medium** | per-tool; no unified hardening checklist |

---

## Theme 1 — Unify the shared vocabulary

The tools already share lane/transport/threat IDs through
[`docs/taxonomy/lanes.yaml`](taxonomy/lanes.yaml). The taxonomy now also has a
machine-readable **surface lens** ([`surfaces.yaml`](taxonomy/surfaces.yaml)) and
an **OWASP MCP Top 10 bridge** ([`owasp-bridge.yaml`](taxonomy/owasp-bridge.yaml)),
both CI-gated. The remaining work extends that single-source-of-truth discipline
to the last hard-coded threat-ID consumers.

- [x] **First-class OWASP MCP Top 10 bridge.** Published
  [`docs/taxonomy/owasp-bridge.{yaml,md}`](taxonomy/owasp-bridge.md) as a
  faithful, CI-gated projection of the `owasp_mcp` field in `lanes.yaml` — the
  translation layer for teams that speak OWASP terms. Remaining: normalize the
  19 threats carrying out-of-range placeholder values into MCP01–MCP10 (a
  reviewed, per-threat taxonomy decision).
- [ ] **Taxonomy as a contract, enforced in CI.** `scripts/check_coherence.py`
  now gates `surfaces.yaml` and `owasp-bridge.yaml` against `lanes.yaml`, and
  `lanes.yaml` is consumed by `mcpnuke --coverage-report` and nullfield policy
  generators. Extend the same gating to camazotz `scenario.yaml` threat IDs and
  any other tool that hard-codes them.
- [ ] **Document tool lineage.** A short "how the tools relate" note: which tool
  enforces (nullfield), which finds (mcpnuke), which measures (stoneburner),
  which is the target (camazotz) — plus a clear statement of what each tool
  supersedes from earlier prototypes, so new readers aren't confused by
  overlapping capabilities.

---

## Theme 2 — Promote defensive operations into the hub

The hub explains the *defense architecture* well. It is comparatively thin on the
*operational* layer a blue team actually runs. This is the highest-value content
gap to close.

- [ ] **Detection catalog.** A consolidated set of detection rules (pseudo-logic
  + data sources + severity + response action) keyed to MCP-T IDs — covering
  token replay, confused-deputy, tool poisoning, SSRF-to-metadata, audit
  evasion, shadow servers, and context leakage.
- [ ] **Incident-response playbooks.** Per-incident-type IR runbooks (the top
  MCP incident classes) with detection → triage → contain → eradicate → recover
  steps and SLAs.
- [ ] **Controls-to-findings traceability.** A matrix mapping
  MCP-T → control → detection → IR playbook → owner, so a finding from mcpnuke
  has a clear path to an enforced control and a monitored detection.
- [ ] **Kill-switch automation patterns.** Document the automated containment
  hooks (nullfield DENY escalation, credential revocation, deployment scale-down)
  that turn a detection into an action.

---

## Theme 3 — Close the purple-team loop

Today the loop is scan (mcpnuke) → enforce (nullfield) → validate (mcpnuke). The
missing half is **did the attack trip a detection?** This connects all four
tools into a measurable purple-team cycle.

- [ ] **Attack → alert correlation.** A harness that runs a known attack
  (camazotz lab or adversarial fixture) and asserts the corresponding detection
  fired, producing a pass/fail per MCP-T category.
- [ ] **SIEM integration references.** Export shapes for Splunk HEC, Elastic, and
  Datadog so detections can be wired into existing pipelines.
- [ ] **MTTD/MTTR tracking spec.** Define how time-to-detect and time-to-respond
  are measured across the loop so coverage can be reported as a trend.
- [ ] **Scheduled drills.** A CI workflow that runs the purple-team loop on a
  cadence and flags regressions (a detection that stopped firing, a control that
  drifted open).

---

## Theme 4 — Mature & harden the tools themselves

Securing the tools that secure MCP. A unified hardening baseline across all four.

- [ ] **Supply-chain baseline.** Pinned dependencies, SBOM generation, and
  signed releases for nullfield, mcpnuke, and stoneburner.
- [ ] **Authz on the tools' own surfaces.** nullfield's admin/policy endpoints,
  mcpnuke's scan API, and any stoneburner control surface should require
  authenticated, scoped access — the arbiter must not be a soft target.
- [ ] **Secret-handling audit.** Confirm no tool persists upstream credentials,
  inference API keys, or scan targets to disk or logs; document the per-tool
  secret lifecycle. (stoneburner already moved its local `.env` out of the repo
  and scrubs key-like strings; generalize that discipline.)
- [ ] **stoneburner `archreview` as a tooling-fidelity gate.** The new
  security-architecture review benchmark can score how well candidate models
  identify the OWASP MCP Top 10 categories in camazotz itself — turning the
  vulnerable target into a reusable answer key for model selection.

---

## Theme 5 — Documentation hygiene (continuous)

- [ ] Keep tool badges and reference headers in sync with releases (version,
  test count, schema version) — enforced by `scripts/check_coherence.py`.
- [ ] Each tool reference page states its current version, what's new since the
  last hub sync, and any known drift.
- [ ] Cross-repo links resolve; private-only references are never published.

---

## Principles

1. **One vocabulary.** Every tool maps to the same lane/transport/threat IDs.
   New capabilities extend the taxonomy; they do not fork it.
2. **Research first, tooling second.** A documented threat model precedes a
   scanner module or detection rule.
3. **Public-safe by default.** No live targets, credentials, or private
   infrastructure paths in the hub. Synthesize research into general patterns.
4. **Closed loop.** Every attack should map to a control, a detection, and a
   regression check. Coverage is measured, not assumed.
