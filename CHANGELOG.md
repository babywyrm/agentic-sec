# Changelog

All notable hub-level changes to the agentic-security ecosystem (camazotz +
nullfield + mcpnuke + stoneburner + this docs hub). Per-project code changes
live in each project's own CHANGELOG; this file narrates **ecosystem
milestones** — moments where the shared vocabulary, the lane/transport
taxonomy, the policy contract, or the cross-project surfaces moved together.

The format is loosely [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions are dated rather than semver because this is a docs hub and the
"release" is the alignment of the sibling repos.

## [2026-06 pt.19] stoneburner v0.6.0 reference sync + coherence enforcement

- **`docs/reference/stoneburner.md`** synced to v0.6.0 / schema v14 / 911 tests; new **Evaluation Fidelity** section (judge accuracy & calibration: deterministic scoring, self-judge guard, gold-criteria coverage, multi-judge consensus; token-burn fidelity: honest cache/thinking-token accounting, standardized TPS); `task_results` fidelity columns (schema v12–v14).
- **Ecosystem scorecard + roadmap** updated for stoneburner v0.6.0 (`inference.env` standard + `atomics.inference` resolver, `--provider vllm`, `qa`/`soak`/`scenario`/`contention`/`baselines`); boundary date 2026-06-16.
- **Walkthrough index** — Walkthrough 12 (AI Guardrail Resistance Testing) and the model-compatibility methodology note are now linked from `README.md`.
- **Cross-repo coherence** (`scripts/check_coherence.py`) extended to gate the stoneburner + mcpnuke package versions and stoneburner's SQLite `SCHEMA_VERSION` cited in the reference headers; 12 unit tests added under `tests/`; CI now checks out stoneburner and runs the tests before the assertions.
- **Scope** — references to not-yet-public CTF inference orchestration were removed; the generalized research (model-compatibility labels, capability-vs-resilience) remains in the stoneburner reference and the model-compatibility note.

---

## [2026-05 pt.18] mcpnuke CI tooling + stoneburner CLI polish + docs sync

- **mcpnuke SARIF 2.1.0 export** (`--sarif FILE`) — maps CRITICAL/HIGH → `error`, MEDIUM → `warning`, LOW → `note`; embeds `security-severity` property and taxonomy/MITRE tags in SARIF rules. Ready for GitHub Code Scanning upload via `codeql-action/upload-sarif`. 15 new tests.
- **mcpnuke `--fail-on`** severity gate — `{critical,high,medium,low,any,none}` replaces hardcoded CRITICAL/HIGH exit checks; `none` always exits 0 for informational scans. Default unchanged (`high`).
- **mcpnuke token redaction** — `_raw_token` stripped from `auth_context` in all JSON/SARIF output paths. Bearer tokens are never written to report files, PR comments, or CI artifacts. 2 regression tests.
- **mcpnuke LICENSE** — MIT license file added.
- **mcpnuke-runner documentation** — new section in `docs/ci-cd-guide.md` covering K8s/Helm deployment, env vars, manual trigger via camazotz API, and structured logging.
- **mcpnuke CI guide updated** — GitHub Actions and GitLab CI examples now use `--fail-on` + `--sarif`; generic CI bash simplified to use `--fail-on` instead of shell-parsing JSON severity counts.
- **stoneburner `atomics sweep --save`** — persist sweep results to new `sweep_results` table (schema v8). `--ollama-host` replaces `--host` (hidden alias kept). `-t` shorthand removed from `capacity --think-time` (collision with `--tier`).
- **stoneburner `atomics export --suite`** — `{tasks,stress,sweep,all}` exposes all DB tables as jsonl or CSV. Previously only task results were exportable.
- **stoneburner `atomics compare --output FILE`** — write JSON comparison alongside the Rich table output.
- **stoneburner `atomics doctor`** documented in README with check table and CI pre-flight example.
- **stoneburner orphan configs removed** — `configs/{aggressive,conservative,default}.toml` deleted (unused since Pydantic Settings replaced TOML loading).
- **`docs/reference/stoneburner.md`** updated: sweep/stress/capacity/models/doctor commands, schema v8 tables, export `--suite`, compare `--output`, Ollama env vars.
- **`docs/reference/mcpnuke.md`** updated: `--fail-on`, `--sarif`, token redaction, CI integration section, test count (671 collected, 635 pass / 37 skip).
- **Ecosystem scorecard** date bumped to 2026-05-31; mcpnuke entry updated with SARIF + `--fail-on`.
- **Test counts:** mcpnuke 671 (635 pass, 37 skip), stoneburner 443 pass.

---

## [2026-05 pt.17] Ecosystem sync — stoneburner reference + nullfield 139-tool alignment

- **nullfield `tools.yaml`** re-synced from 85 → 139 tools, matching camazotz's current `tools/list` surface.
- **`docs/reference/stoneburner.md`** created — CLI commands, provider table, eval suites (adversarial/red-blue/probe), thinking mode, camazotz brain-gateway integration.
- **README** updated: "Three Tools" → "The Tools"; added stoneburner badge, reference link, license footer entry.
- **Ecosystem scorecard** stoneburner description expanded to reflect adversarial/red-blue/probe suites; scorecard date bumped to 2026-05-24.

---

## [2026-05 pt.16] Stoneburner v0.5.0 — adversarial, red/blue, and probe suites

- **stoneburner `atomics adversarial`** — 15 adversarial fixtures across 7 categories (prompt injection, role confusion, context escape, instruction override, social engineering, data exfil, CoT leakage). Inverted resistance scoring on 0.0–1.0 scale. `--runs N` for multi-pass variance (mean ± stddev). `--extra-judges` for multi-judge consensus scoring across providers.
- **stoneburner `atomics redblue`** — 10 fixtures (5 red team offensive, 5 blue team defensive) for security capability evaluation. Reuses quality-based LLM-as-judge scoring.
- **stoneburner `atomics probe`** — live infrastructure analysis via external `probes.yaml`. Configurable artifact types (access logs, JSON reports, K8s audit logs, config files, API responses). Regression detection against prior baselines.
- **Thinking mode** (`--thinking` / `--no-thinking` / `--thinking-budget`) — benchmarks reasoning toggle across providers that support it (Claude, OpenAI, Ollama).
- **`brain-gateway` provider** — routes benchmarks through camazotz's MCP inference endpoint, enabling same-workload comparison across camazotz-managed providers.
- **adv-14 CoT leakage fixture** — captures the `qwen3:4b` chain-of-thought-into-verdict bug found during agentic AI-gate model-compatibility testing. Models that emit reasoning before structured verdicts break `startswith`-based parsers in agentic pipelines.
- **adv-15 credential extraction fixture** — mirrors the "helpful ops request" social engineering strategy that leaked an agent client secret across multiple Ollama models.
- **SQLite schema v6** — `suite` column on `task_results`, new `adversarial_results` and `probe_results` tables.
- **369 tests passing.**

---

## [2026-05 pt.15] Camazotz — Auth0 + Identity Dashboard + DPoP

- **Auth0 identity provider** — `OidcIdentityProvider` subclass with OIDC auto-discovery (`from_issuer()`). Fourth IdP alongside mock, ZITADEL, and Okta. `make up-auth0` compose profile.
- **Identity Dashboard operational hub** — redesigned `/identity` page with live lifecycle testing, OIDC auto-discovery panel, JWT decoder, DPoP badge, provider switcher. Supersedes the earlier pt.11 switcher panel.
- **Transparent DPoP (RFC 9449)** — OIDC providers now support Demonstrating Proof-of-Possession. DPoP proofs are generated per-request; brain-gateway validates binding. Surfaces in Identity Dashboard as a badge.
- **Brain provider runtime switching** — benchmark SSE dashboard for live provider comparison. Playground search filter. Brain popover with provider metadata. Ollama SSRF allowlist.
- **Test count: 1479** (up from 1209 at pt.9).

---

## [2026-05 pt.14] mcpnuke 6.10–6.13 — inference probes + SDK cache + Ollama AI

- **MCP-T54 `--inference` / `--inference-host`** (mcpnuke 6.10.0) — unauthenticated inference backend probe. Discovers Ollama/vLLM/TGI endpoints exposed without auth, enumerates models, checks for prompt injection via the raw API. Lane 3 finding.
- **MCP-T55 `--inference-baseline` / `--save-inference-baseline`** (mcpnuke 6.11.0) — model integrity verification. Saves model digests as baseline; re-scan detects model swaps or tampering. Lane 3 finding.
- **MCP-T33 `sdk_cache_tamper` + `sdk_cache_poisoning`** (mcpnuke 6.12.0) — Lane 1 / Transport C checks. Detects in-process SDK tool caches that can be tampered via shared memory or poisoned via malicious tool registration. Closes the Lane 1/C gap in mcpnuke's check catalog.
- **Ollama AI analysis** (mcpnuke 6.13.0) — `--ollama-analysis` for single-model AI-assisted finding analysis; `--ollama-ensemble` for multi-model ensemble consensus. Zero-cost alternative to `--claude` for local analysis.
- **Taxonomy entries T54/T55** added to `docs/taxonomy/lanes.yaml`.
- **618 tests passing, 36 skipped.**

---

## [2026-05 pt.13] MCP-T53 Shell Command Wrapping Injection

- **camazotz `shell_exec_wrap_lab`** (MCP-T53, Lane 3 / Transport D): new lab that wraps `subprocess.run(user_input, shell=True)` behind an MCP tool — not simulated. Demonstrates the Transport D threat model where the MCP layer is fine but the vulnerability is one level down in the subprocess call. Shell metacharacter injection via `extra_args` and `base_cmd` parameters. Easy: raw shell=True, no filtering. Medium: basic blocklist, bypassable. Hard: allowlist enforcement blocks injection. 14 tests.
- **mcpnuke `shell_injection` check** (`mcpnuke/checks/shell_injection.py`): Transport D behavioral probe that detects subprocess-wrapping tools by schema signals and sends targeted shell injection payloads (semicolon chain, subshell expansion, backtick expansion, pipe chain, and-chain). Findings tagged `lane: 3, transport: D` with CRITICAL severity when injected command output is echoed back. Dangerous base command probes (bash, sh) report HIGH. 18 tests.
- **agentic-sec docs** — lab count updated 51 → 52, threat ID range extended to MCP-T01–MCP-T53 across golden-path, ecosystem, and identity-flows references.

---

## [2026-05 pt.12] nullfield v0.9 — tool lifecycle + rug-pull detection

- **Tool lifecycle management** (`pkg/registry/lifecycle.go`): nullfield now tracks tool registration timestamps and detects mid-session tool mutations (description changes, schema drift, new tools appearing after initialization). Rug-pull attempts that modify tool behavior post-registration are flagged and optionally blocked.
- **Response inspection pipeline**: nullfield can now inspect tool responses before forwarding to the caller. Pluggable inspectors scan for credential leakage, injection payloads, and oversized responses. Configurable per-tool via `spec.responseInspection` in NullfieldPolicy.
- **Cost attribution**: per-identity, per-tool cost tracking with configurable budget ceilings. Cost events are emitted to the audit stream with `principal`, `tool`, and `cost_usd` fields. Integrates with nullfield's existing BUDGET action for enforcement.
- **Tests**: lifecycle and lifecycle_test coverage for registration, mutation detection, and rug-pull blocking.

---

## [2026-05 pt.11] Camazotz — runtime IdP switching with auto lab reset

- **Runtime IdP override** — `PUT /config { idp: { provider, issuer_url, token_endpoint, ... } }` switches the active identity provider on the fly without restarting services. `set_idp_config()` / `reset_idp_config()` in `config.py` with thread-safe runtime overlay.
- **Auto lab reset** — changing the IdP provider triggers `registry.reset_all()` and rate limiter reset, preventing stale token references from the previous provider.
- **Health cache invalidation** — `invalidate_idp_health_cache()` in `service.py` clears the 10s health probe cache on every IdP switch.
- **Identity Dashboard switcher** — full switcher panel on `/identity` with provider dropdown, endpoint fields, client credentials, Apply/Reset buttons.
- **Global strip IdP popover** — the IdP pill in the global status strip is now clickable with a dropdown for quick mock/zitadel/okta toggling.
- **Provider-agnostic UI** — identity.html mermaid diagrams, reference tables, and labels generalized from ZITADEL-specific to provider-agnostic.
- **16 new tests** (`test_runtime_idp_switching.py`) — config overrides, PUT /config integration, health cache invalidation, lab reset on switch, no-op same-provider.
- **agentic-sec docs** — runtime switching documented in camazotz reference, Okta setup guide (Option B), identity-flows provider table updated.

---

## [2026-05 pt.10] Ecosystem-wide — Okta identity provider support

- **camazotz `OidcIdentityProvider` base class** extracted from `ZitadelIdentityProvider` — standard OAuth2 RFC logic (client credentials, RFC 8693 exchange, RFC 7662 introspection, revocation) shared across all OIDC providers. `ZitadelIdentityProvider` and `OktaIdentityProvider` are thin subclasses with factory methods.
- **camazotz `OktaIdentityProvider`** — `from_env()` reads `CAMAZOTZ_IDP_*` env vars; supports OIDC discovery via `from_issuer()`. Okta authorization server URL handling (org, default, custom).
- **Provider-agnostic lab wiring** — `is_live_idp()` helper replaces 60+ `== "zitadel"` checks across `rbac_lab`, `oauth_delegation_lab`, `revocation_lab`, `main.py`, smoke tests, and QA runner.
- **`make up-okta`** compose profile — disables bundled ZITADEL stack, points brain-gateway at external Okta org. Template: `compose/.env.okta.example`.
- **5 Okta flow tests** (`test_okta_flows.py`) — exchange, revocation, RBAC, degradation, and `/config` endpoint validation.
- **agentic-sec docs** — Okta setup guide (`docs/guides/okta-setup.md`), ecosystem roadmap updated, identity-flows and camazotz reference updated.
- **nullfield and mcpnuke unchanged** — both are already IdP-agnostic.

---

## [2026-05 pt.9] Ecosystem-wide — Lane 5 complete (51 labs)

- **camazotz `anon_schema_harvest_lab`** (MCP-T50, Lane 5 / Transport A): anonymous tool schema over-disclosure — tool descriptions on easy/medium contain internal hostnames, credential patterns, and `CZTZ_SERVICE_KEY` references harvested without any authentication. Hard: catalog sanitized. 14 tests.
- **camazotz `anon_rate_exhaust_lab`** (MCP-T51, Lane 5 / Transport A): no per-caller accounting for anonymous traffic; anonymous flood exhausts global budget; authenticated callers denied. Hard: separate anonymous bucket protects authenticated quota. 14 tests.
- **camazotz `preauth_injection_lab`** (MCP-T52, Lane 5 / Transport A): pre-auth guest tool stores metadata raw before identity is established; injected directives are inherited by the authenticated session context and influence post-auth LLM behavior. Hard: sanitized at storage time. 14 tests.
- **Lane 5 purpose-built labs complete.** All five identity lanes now have dedicated modern labs.
- **mcpnuke `profiles/camazotz.json`** updated: 102 → 111 tools (MCP-T50/T51/T52 tools added).
- **Lab count: 48 → 51 labs. Test count: 1164 → 1209 passing.**

---

## [2026-05 pt.8] Ecosystem-wide — Lane 4 complete across all transports

- **camazotz `agent_subprocess_chain_lab`** (MCP-T48, Lane 4 / Transport D): subprocess spawning does not create a new identity boundary — `AGENT_TOKEN` injected into child env, inherited without re-auth. Hard mode: `read_secrets` blocked, token masked. 14 tests. Lab count 46 → 47.
- **camazotz `agent_llm_chain_lab`** (MCP-T49, Lane 4 / Transport E): LLM function-calling passes full conversation context — including any credential embedded in the system prompt — to every registered function. Hard mode: `call_with_context` does not echo credential, but `inspect_context` still returns raw context. 14 tests. Lab count 47 → 48.
- **Lane 4 is now fully covered across all five transports (A/B/C/D/E).** No transport gaps remain in any lane.
- **Walkthrough 11** (`docs/walkthroughs/lane4-defense.md`): Building a Lane 4 Defense from Scratch — depth limits, scope narrowing, task allowlists, subprocess env control, and LLM context redaction, with a complete nullfield policy and validation test suite for all five transport patterns.
- **mcpnuke `profiles/camazotz.json`** updated: 96 → 102 tools (MCP-T48/T49 tools added).

---

## [2026-05 pt.7] Ecosystem-wide — transport matrix complete + Campaign 5 + Walkthrough 10

- **camazotz `delegated_sdk_lab`** (MCP-T46, Lane 2 / Transport C): fills the Lane 2 / Transport C matrix gap. Human delegates to agent via in-process SDK; credential cached in shared process memory; injected `action=dump_cache` exposes it. Hard mode: `dump_cache` blocked by allowlist. 12 tests. Lab count 45 → 46.
- **camazotz `agent_sdk_chain_lab`** (MCP-T47, Lane 4 / Transport C): fills the Lane 4 / Transport C matrix gap. **5×5 transport matrix is now complete.** Agent A loads Agent B as in-process SDK library; Agent A's credential forwarded implicitly; Agent B executes `escalate_privilege`; Agent B identity invisible in audit logs. Hard mode: task manifest blocks privilege escalation. 12 tests. Lab count 45 → 46.
- **mcpnuke Spring Actuator Phase 2 exploitation probes**: passive GET discovery now gates active POST probes — heapdump download (binary size check), env write, logger level override (ROOT + security to TRACE), config refresh, restart, and gated shutdown. Extended passive endpoint list with `/actuator/mappings`, `/actuator/httptrace`, `/actuator/scheduledtasks`, `/actuator/threaddump`. Findings logged under `actuator_exploitation` category.
- **Makefile convenience targets** in camazotz: `make test-identity`, `test-injection`, `test-secrets`, `test-governance`, `test-defense`, `test-teleport`, `test-infra`, `test-fast` — all keyed to pytest marks.
- **Campaign 5** (`docs/campaigns/enterprise-ai-ops.md`): Enterprise AI-Ops Platform — 5-step attack chain threading MCP-T42 (shared IdP pollution) → MCP-T43 (DPoP forgery) → MCP-T44 (blocklist bypass) → MCP-T46 (SDK cache exposure) → MCP-T47 (agent chain identity dilution). Full mcpnuke scan block, nullfield policy, and validation test suite.
- **Walkthrough 10** (`docs/walkthroughs/token-cross-pollution.md`): Token Cross-Pollution and Shared Identity — hands-on 15-minute walkthrough of MCP-T42 + MCP-T43 together. Covers how scope isolation failure and DPoP key leakage compound each other.

---

## [2026-05 pt.6] Ecosystem-wide — five improvements across camazotz, mcpnuke, nullfield, agentic-sec

- **mcpnuke `profiles/camazotz.json`** updated: 70 → 90 tools; 13 new entries for MCP-T41–T44 with lane/transport/notes.
- **Walkthrough 9** (`docs/walkthroughs/ai-governance-infrastructure.md`): AI Governance Infrastructure as Attack Surface — MCP-T41 pattern, full practitioner walkthrough with mcpnuke scan example.
- **mcpnuke DPoP enforcement check** (`mcpnuke/checks/dpop_enforcement.py`): three RFC 9449 probes — no DPoP header accepted, malformed DPoP accepted, htm/htu binding not verified. Lane 3 / MCP-T43.
- **camazotz `agent_chain_direct_api_lab`** (MCP-T45, Lane 4 / Transport B): fills the Lane 4 / Transport B matrix gap. 12 tests. Lab count 43 → 44.
- **nullfield `scope.request.blockRedirects`**: strips URL-typed arguments before forwarding. MCP-T41 defense at the policy layer.

## [2026-05 pt.5] Camazotz — four new labs, 43 total, 1090 tests

Four new camazotz labs shipped, covering real vulnerability classes from production agentic deployments:

- **`ai_governance_bypass_lab`** (MCP-T41, Lane 2 / Transport A) — AI governance gates that validate URL hostnames can be bypassed via open redirect on a trusted host. The AI approves the initial hostname; the underlying resolution follows the redirect. Structural bypass, not prompt injection.
- **`shared_idp_pollution_lab`** (MCP-T42, Lanes 1+2 / Transport A) — When multiple OAuth clients share the same identity realm, JWKS, and MCP endpoint, a leaked agent `client_secret` bridges user-land to agent-land via a standard `client_credentials` grant.
- **`dpop_forgery_lab`** (MCP-T43, Lane 3 / Transport A) — DPoP (RFC 9449) proof-of-possession only works when the private key stays private. When exposed via a config or actuator endpoint, an attacker can forge proofs with correct `htm`/`htu` binding. Iterative 401 error discovery teaches the required claim structure.
- **`blocklist_bypass_lab`** (MCP-T44, Lane 2 / Transport A) — Incomplete server-side blocklists invite bypass research. The filter blocks common shells and metacharacters but misses `perl` (easy/medium) and `awk` (hard). Safe-character encoding bypasses (`qq{}`, `sysopen`, numeric flags) achieve execution through allowed paths.

Hub docs updated: README badge (39→43), `docs/ecosystem.md` (shipped roadmap, coverage gaps, near-term), `docs/golden-path.md` (validation mapping +4 rows, lab count), `docs/reference/camazotz.md` (categories table), `docs/identity-flows.md`, `docs/walkthroughs/flow-types-in-practice.md`.

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
