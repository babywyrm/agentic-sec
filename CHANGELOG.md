# Changelog

All notable hub-level changes to the agentic-security ecosystem (camazotz +
nullfield + mcpnuke + this docs hub). Per-project code changes live in each
project's own CHANGELOG; this file narrates **ecosystem milestones** —
moments where the shared vocabulary, the lane/transport taxonomy, the
policy contract, or the cross-project surfaces moved together.

The format is loosely [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions are dated rather than semver because this is a docs hub and the
"release" is the alignment of the three sibling repos.

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
