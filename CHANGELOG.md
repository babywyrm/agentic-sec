# Changelog

All notable hub-level changes to the agentic-security ecosystem (camazotz +
nullfield + mcpnuke + this docs hub). Per-project code changes live in each
project's own CHANGELOG; this file narrates **ecosystem milestones** —
moments where the shared vocabulary, the lane/transport taxonomy, the
policy contract, or the cross-project surfaces moved together.

The format is loosely [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions are dated rather than semver because this is a docs hub and the
"release" is the alignment of the three sibling repos.

## [2026-05 pt.4] Docs polish — README, CONTRIBUTING, walkthrough fixes

- **README rewrite:** Trimmed from 608 → ~200 lines. Deep content (architecture diagrams, coverage matrix, per-project deep dives) now lives in `docs/ecosystem.md` where it belongs. README is now a clean landing page.
- **CONTRIBUTING.md:** Added. Covers walkthroughs, campaign scenarios, reference updates, vocabulary/taxonomy changes, style guide.
- **golden-path.md v3.1:** Removed internal-org framing; added ecosystem tool map (nullfield→Gates 3–5, ZITADEL/Teleport→Gate 2, mcpnuke→validation); made IdP references generic; fixed broken assessment-framework URL.
- **Markdown quality pass:** Fixed broken GitHub URL, invalid JSON code block, lab count drift (35→39) across 5 files, threat ID column normalization (MCP-Txx) across 4 campaign docs, missing Walkthrough 8 in README table, empty table header in deployment-guide, ragged cell in identity-flows.
- **Cleanup:** Removed internal planning artifacts (`docs/superpowers/`, `docs/specs/`) from public repo; replaced hardcoded node IPs with `<NODE_IP>` placeholder; removed internal-org language.
- **mcpnuke reference:** Coverage, diff, and profile system docs updated to match current tool output.

## [2026-05 pt.3] Ecosystem Feedback Loop — Scenario Flag + Persistent Policies

Closes the two ecosystem integration gaps identified during the Campaign A
live walkthrough:

**Gap 1 — `feedback_loop.py` `--scenario` flag (camazotz)**
The feedback loop now accepts `--scenario <name>` to run a full campaign
cycle with a single command.  Passing the flag:

- Prints a scenario banner (name, description, policy-name, focus-tools).
- Skips the mcpnuke `--generate-policy` step.
- Instead copies the pre-authored policy from `kube/policies/<scenario>.yaml`
  and applies / diffs against it.

Available names: `customer-support-bot`, `cicd-pipeline-agent`,
`code-review-agent`, `multi-tenant-saas`.

**Gap 2 — `kube/policies/` pre-authored NullfieldPolicy CRDs (camazotz)**
Four hand-tuned `NullfieldPolicy` manifests now live in the repo — one per
campaign.  They are derived from the mcpnuke auto-generated output and
extended with scenario-specific comments explaining the threat rationale:

| File | Key rules |
|---|---|
| `customer-support-bot.yaml` | DENY secrets + webhooks, HOLD egress, SCOPE auth + relay |
| `cicd-pipeline-agent.yaml` | DENY HTTP bypass, SCOPE subprocess, HOLD config writes |
| `code-review-agent.yaml` | DENY tool registration from PR content, SCOPE shell, HOLD URL fetch |
| `multi-tenant-saas.yaml` | DENY cross-tenant, SCOPE RAG synthesizer, DENY delegation depth > 2 |

**New Makefile targets (camazotz)**

```
make campaign-print SCENARIO=customer-support-bot
make campaign       SCENARIO=cicd-pipeline-agent K8S_HOST=192.168.1.85
make campaign-list
```

`campaign-print` does a live baseline scan, shows the pre-authored policy,
but does not apply.  `campaign` is the full round-trip.  `SCENARIO` defaults
to `customer-support-bot` so a plain `make campaign` always has a meaningful
demo value.

Extends the platform's teaching mission with four named deployment personas
(campaigns) that chain multiple labs into end-to-end attack + defend +
validate narratives, and two new camazotz labs that fill the D/Lane 2 and
C/Lane 4 matrix gaps.

### agentic-sec (docs hub)

- **`docs/campaigns/`** — New directory. Four campaign documents, each one a
  named deployment scenario that exercises the full three-tool ecosystem
  (camazotz + mcpnuke + nullfield) together:
  - **`customer-support-bot.md`** — FinTech AI support agent (Transport A,
    Lane 1). Attack chain: `context_lab` → `secrets_lab` → `egress_lab` →
    `shadow_lab`. Prompt injection → credential exfil → SSRF → persistence.
  - **`cicd-pipeline-agent.md`** — Platform deployment bot (Transport B+D,
    Lane 3). Attack chain: `subprocess_lab` → `agent_http_bypass_lab` →
    `config_lab` → `attribution_lab`. Canonical use of `make feedback-loop-apply`.
  - **`code-review-agent.md`** — Cursor/Copilot-style review agent (Transport
    C+D, Lane 1→2). Attack chain: `code_review_agent_lab` → `indirect_lab` →
    `langchain_tool_lab` → `cost_exhaustion_lab`.
  - **`multi-tenant-saas.md`** — B2B SaaS AI feature, 50 tenants, shared RAG
    (Transport C, Lanes 1/2/4). Attack chain: `tenant_lab` →
    `rag_injection_lab` → `delegation_chain_lab` → `attribution_lab`.
- **`docs/campaigns/README.md`** — Campaign index with prerequisites, time
  estimates, and transport/lane coverage per campaign.
- **`docs/learning-path.md`** — Added Track 4 (Campaign Mode, ~5 hours total)
  linking all four campaigns.
- **README.md** — "Run a full deployment scenario" row added to Start Here
  table. Lab count updated 37 → 39.

### camazotz

- **`code_review_agent_lab`** (MCP-T38, Transport D, Lane 2) — Fills the
  D/Lane 2 matrix gap. Simulates a Cursor/Copilot-style review agent that
  shells out using PR content. Shell injection via `extra_args` on easy,
  env-var injection on medium, sandboxed allowlist on hard. 14 unit tests.
- **`rag_injection_lab`** (MCP-T39, Transport C, Lane 4) — Fills the C/Lane 4
  gap. Simulates a two-agent LangChain/LlamaIndex-style RAG pipeline. Poisoned
  document in shared knowledge base hijacks Synthesizer agent output. Content
  passed verbatim on easy, chunked on medium, UNTRUSTED-CONTENT fenced on
  hard. 14 unit tests.
- **QA harness** updated for both new labs.
- **Lab count** updated 37 → 39 in badge and text.

## [2026-05] Teaching Platform Expansion

The platform's primary character as a **teaching platform** for security
practitioners new to MCP and agentic AI is now expressed across all three
repos and the docs hub. This milestone delivers the curriculum layer, fills
two transport-surface lab gaps, and uplifts unit-test coverage in camazotz
and nullfield.

### agentic-sec (docs hub)

- **`docs/bridge.md`** — New "Bridge Document". Maps REST/API security
  knowledge (OWASP Top 10, JWT, SSRF, confused deputy) directly to the MCP
  threat model. Includes an OWASP MCP Top 10 quick-map table, the five
  transport surface reference with real-world runtimes, and the five-lane
  identity matrix with security implications.
- **`docs/learning-path.md`** — Structured curriculum with three tracks:
  Red Team (~4h), Blue Team (~3h), Full Loop (~3h), each with explicit
  pre-requisites, step-by-step pointers to walkthroughs and references, and
  "you will be able to when done" success criteria.
- **`docs/walkthroughs/beyond-mcp.md`** — Walkthrough 8. Traces a single
  attack objective across all five transport surfaces (A–E), showing how the
  attacker's approach, the defender's control point, and the evidence trail
  change at each layer. Pairs with `langchain_tool_lab` and
  `agent_http_bypass_lab`.
- **README.md** — "Start Here" decision table prepended above the main
  content. Routes practitioners to `bridge.md`, `learning-path.md`, and
  walkthroughs before they hit the architecture docs. Badge and content
  references updated from 35 to 37 labs.
- **`docs/specs/2026-05-03-roadmap-expansion-design.md`** — Design spec
  for this milestone (Curriculum-First / Bridge-the-Gap approach).
- **`docs/superpowers/plans/2026-05-03-roadmap-expansion.md`** — Detailed
  12-task implementation plan.

### camazotz

- **`langchain_tool_lab`** (MCP-T36, Transport C, Lane 2) — New lab covering
  LangChain `@tool` description injection. Three-tier difficulty: easy
  (verbatim pass-through), medium (keyword filter), hard (allowlist
  validation). Includes `scenario.yaml` and 13 unit tests.
- **`agent_http_bypass_lab`** (MCP-T37, Transport B, Lane 3) — New lab
  covering machine-agent direct HTTP bypass. Models the vulnerability where
  an agent calls the tool server's raw HTTP API, evading MCP-layer controls
  and nullfield policy. Three-tier difficulty: easy (no auth), medium (leaked
  API key in tool description), hard (mTLS required). Includes `scenario.yaml`
  and 12 unit tests.
- **`scripts/qa_runner/checks.py`** — QA harness extended with
  `test_langchain_tool_lab` and `test_agent_http_bypass_lab` entries.
- **`scripts/feedback_loop.py`** — Extended with `--scanner` (4-tier
  discovery), `--apply-backend` (auto-detect docker-compose vs kubectl),
  `--ssh-key`, `--compose-policy-path`. Full test coverage in
  `tests/test_feedback_loop.py`.
- **Unit tests** — New test files for all 8 previously-untested labs:
  `auth`, `context`, `egress`, `relay`, `secrets`, `comms`, `shadow`, `supply`.

### nullfield

- **`pkg/proxy/handler_test.go`** — New tests for `handler.go` and
  `gateway.go` (policy dispatch, HOLD/DENY/ALLOW/SCOPE/BUDGET, identity
  extraction).
- **`pkg/identity/identity_test.go`** — New tests for `HeaderVerifier`,
  `NoopVerifier`, `WithIdentity`/`FromContext`, `MultiVerifier`.
- **`pkg/identity/jwks_test.go`** — New tests for `JWKSVerifier` including
  `DATA RACE` fix (replaced `bool` with `atomic.Bool` in hot-loader).

## [2026-04] Ecosystem Alignment Sweep

A coordinated milestone across all four repos: the lane/transport
vocabulary expanded, the lab catalog grew, a true policy-enforced K8s
entry point shipped, and mcpnuke gained the cross-project reporting it
needed to be honest about coverage.

### Taxonomy

- **Five-transport taxonomy ratified** (was three).
  Codes `D` (subprocess / native binary) and `E` (native LLM
  function-calling, non-MCP) joined the stable taxonomy after two spike
  labs validated they are non-degenerate identity envelopes. Decision
  record:
  [camazotz ADR 0001](https://github.com/babywyrm/camazotz/blob/main/docs/adr/0001-five-transport-taxonomy.md).
  All four repos now key on `A`/`B`/`C`/`D`/`E`.
- **35 vulnerable labs in camazotz** (was 32).
  Three new labs landed:
  - `sdk_tamper_lab` (Lane 1 / Transport C) — closes Lane 1 baseline
    transport coverage.
  - `subprocess_lab` (Lane 3 / Transport D) — first ADR-0001 spike lab.
  - `function_calling_lab` (Lane 2 / Transport E) — second spike lab.
- Lane slugs (`human-direct`, `delegated`, `machine`, `chain`,
  `anonymous`) and transport codes confirmed as the ecosystem's shared
  vocabulary. Renaming any of them now requires lockstep PRs in
  camazotz, nullfield, mcpnuke, and this hub.

### Lane View shipped

- New camazotz endpoints: `GET /lanes` (HTML — labs grouped by identity
  lane, with per-lane flow diagrams, default nullfield action, covering
  mcpnuke checks, and gaps inline) and `GET /api/lanes` (JSON, schema
  `v1` — the machine-readable contract that sibling tools consume).
- Lane View is the canonical "who is the actor?" lens; `/threat-map`
  remains the parallel "what kind of attack?" lens.

### Nullfield-policed K8s entry point

- `kube/brain-gateway-policed.yaml` introduces a sidecar deployment that
  exposes two NodePorts with deliberately different postures:
  - `:30080` — bypass path, raw brain-gateway, no policy. Red-team scans.
  - `:30090` — policed path, NodePort → nullfield `:9090` → brain-gateway.
    Unauthenticated calls return JSON-RPC `-32001 identity verification
    failed`. The arbiter actually arbitrates.
  - `:31591` — nullfield admin (`:9091`) for policy CRD status, decision
    counters, and audit tail.
- New camazotz make target: `make smoke-k8s-policed`.
- Recommended demo flow: run the feedback loop against **both** ports.
  The diff between the two reports is the value nullfield is adding.

### mcpnuke cross-project reporting

- `--by-lane` — group findings by identity lane (1–5) with per-lane
  severity tallies and a "checks fired / checks defined" coverage
  fraction.
- `--coverage-report <camazotz-url>` — fetch `/api/lanes` schema v1 from
  a live camazotz and emit a cross-project coverage report intersecting
  mcpnuke's finding catalog with camazotz's lane distribution. The
  ecosystem-level report.
- `--generate-policy <fix.yaml>` — emit a ready-to-apply nullfield
  policy YAML directly from findings. Closes the scan → recommend →
  enforce loop in one command.
- New JWT boundary checks in `mcpnuke/checks/jwt_boundary.py`:
  - `jwt_audience_target_match` (HIGH, Lane 1)
  - `jwt_cross_role_replay` (HIGH, Lane 1)
  Together these close the MCP-T04 / Lane 1 audience-and-replay
  coverage gap that previously surfaced in the lane heatmap.

### Brain key asymmetry — operator-visible

- Documented (and intentionally preserved) the contrast in how the two
  cloud-AI surfaces fail when `ANTHROPIC_API_KEY` is unset:
  - **camazotz brain** (`claude-sonnet-4-20250514` via
    `CloudClaudeProvider`) **silently degrades** — responses are
    prefixed `[cloud-stub] ...` text but smoke probes still pass. Useful
    for offline demos; dangerous if you mistake "smoke green" for "real
    LLM in the loop." Operators should grep transcripts for
    `[cloud-stub]` before claiming a Claude-backed run.
  - **mcpnuke `--claude`** **exits loudly** — non-zero, error on stderr,
    scan does not run. Scanner refuses to fake the AI layer.

### Hub docs aligned

- `README.md` — hero badges, architecture diagram, lane × transport
  mermaid grid, K8s Quick Start, brain key asymmetry callout.
- `docs/identity-flows.md` — TOC and body now consistently say "Five
  Transport Surfaces"; the lane × transport matrix carries all 35 labs.
- `docs/reference/camazotz.md` — 35 labs, `/lanes` + `/api/lanes` in Key
  Endpoints, K8s NodePort table including the policed `:30090`.
- `docs/reference/mcpnuke.md` — transport guidance updated to A–E,
  cross-project lane reporting flags documented, JWT boundary checks
  listed.
- `docs/ecosystem.md` — 35 patterns × 5 transports, new Lane View
  paragraph linking the `/lanes` UI and `/api/lanes` JSON contract to
  `mcpnuke --coverage-report`.
- `scripts/feedback-loop.sh` — usage block now documents the bypass vs
  policed K8s ports and recommends running both back-to-back.
