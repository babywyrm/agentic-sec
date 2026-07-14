# Surface Taxonomy

An inventory of the artifacts and control points that exist in an agentic
workspace — the "things you can point at" — with, for each: what it is, why it
exists, the trust it's granted by default, what goes wrong, how to vet it, which
tool owns the check, and when that check runs.

This is the **surface lens**. It complements, and does not duplicate, the other
three:

- The [Attack Path Atlas](../attack-path-atlas.md) organizes by *attack* (domains A–K).
- [`lanes.yaml`](lanes.yaml) organizes by *identity* (five lanes × five transport surfaces A–E).
- This file organizes by *artifact* — the map a human uses to understand what
  each part of the agentic workspace is for and how its risk is vetted.

The machine-readable form is [`surfaces.yaml`](surfaces.yaml).

## How to read an entry

Every surface answers the same questions:

- **Purpose** — why the artifact exists at all.
- **Default trust** — how much implicit trust it's granted today. High trust,
  low review = the dangerous combination.
- **Risk** — what an attacker does with it, cross-linked to Atlas domains and
  `MCP-T*` threat IDs.
- **Vet with** — the ecosystem tool that owns the check (or `manual` where
  nothing covers it yet), and **when** it runs.
- **Fail-closed test** — the abuse test that proves the control *refuses*, not
  merely that the happy path works. A surface is "vetted" only when this test
  exists and fails closed.
- **Coverage** — `strong` / `partial` / `gap`. Gaps drive the roadmap.

## Master map

| Surface | Category | Trusted by default | Vet with | When | Coverage |
|---------|----------|--------------------|----------|------|----------|
| Agent instructions (`AGENTS.md`) | control-plane config | High | skillseraph | pre-commit / CI | strong |
| Skills (`SKILL.md`) | control-plane config | High | skillseraph | pre-commit / CI | strong |
| IDE control files (`.cursor/rules`, hooks) | control-plane config | High | skillseraph | pre-commit / IDE hook | strong |
| MCP server definitions (configs) | control-plane config | High | skillseraph | pre-commit / boot | strong |
| Live MCP servers | runtime | Medium | mcpnuke | CI / runtime | strong |
| Tool registry & schemas | runtime | Medium | nullfield + mcpnuke | runtime | strong |
| The arbiter / enforcement point | runtime | n/a | nullfield | runtime | strong |
| Policy files (NullfieldPolicy, AgenticFlow, CRDs) | runtime | n/a | nullfield | apply / CI | strong |
| CLI / subprocess / native function-calling flows | runtime | Medium | camazotz + mcpnuke | eval / runtime | partial |
| Models / inference backends | model | Medium | stoneburner | eval | strong |
| Evals / benchmarks | model | n/a | stoneburner | eval / CI | strong |
| Identity, tokens, credentials | identity | High | platform (Teleport/ZITADEL) + nullfield | runtime | partial |
| Memory / RAG / state | model | High | camazotz (Domain C) | eval | partial |
| Audit / observability | infra | n/a | nullfield audit + detection | runtime | partial |
| Automation / CI triggers | control-plane config | High | skillseraph | CI | strong |

---

## Agent instruction files (`AGENTS.md`)

**Category:** control-plane config · **Default trust:** high · **Coverage:** strong

**Purpose.** Standing, repo- or org-level instructions an agent reads before
acting — conventions, do/don't rules, workflow guidance. They exist to make
agents consistent and useful without re-prompting every session.

**Risk.** Trusted by default and rarely reviewed as hostile input. A planted
`AGENTS.md` — including one buried deep in a dependency tree — can override the
agent's behavior, fabricate authority ("approved by security"), suppress
disclosure in PR summaries, or instruct secret exfiltration.
Atlas: `J1`, `J5`. Threats: `MCP-T01`, `MCP-T02`.

**Vet with:** skillseraph — pre-commit, CI, pre-boot.

**Fail-closed test.** Plant an `AGENTS.md` three directories deep in
`node_modules/` containing an instruction-override payload; skillseraph fails CI
at or above `--fail-on`. If CI stays green, the surface is unvetted.

---

## Skills (`SKILL.md`)

**Category:** control-plane config · **Default trust:** high · **Coverage:** strong

**Purpose.** Named, invokable capability definitions the agent loads on demand —
reusable procedures that carry their own instructions.

**Risk.** Invocation-time override, callback/redirect on invoke,
self-modification, silent invocation, or remote skill pull that changes behavior
*after* the skill was reviewed. Atlas: `J2`. Threats: `MCP-T01`, `MCP-T03`,
`MCP-T14`.

**Vet with:** skillseraph — pre-commit, CI.

**Fail-closed test.** Add a `SKILL.md` whose invocation instructions include a
remote fetch plus self-modify; skillseraph flags `skill_invocation` and fails CI.

---

## IDE control files (`.cursor/rules`, hooks, settings)

**Category:** control-plane config · **Default trust:** high · **Coverage:** strong

**Purpose.** IDE- and agent-runtime configuration: rule files, lifecycle hooks
(e.g. `beforeAgentStart`), and editor settings that shape how the agent behaves
locally.

**Risk.** Hooks that run shell on agent start, rules that inject hidden
instructions, or extension/publisher trust that pulls unreviewed automation into
the session. Atlas: `J3`, `J4`. Threats: `MCP-T09`, `MCP-T14`.

**Vet with:** skillseraph (`audit-local` for local IDE config) — pre-commit and
IDE hook.

**Fail-closed test.** Add a hook config that execs a remote bootstrap on
`beforeAgentStart`; `skillseraph audit-local` flags it before the session starts.

---

## MCP server definitions (configs)

**Category:** control-plane config · **Default trust:** high · **Coverage:** strong

**Purpose.** Config that tells the agent which MCP servers and tools exist and
how to reach them — URLs, auth, stdio exec commands, tool schemas.

**Risk.** A poisoned server definition: remote or raw-IP URLs, env-credential
injection, stdio exec, TLS disabled, wildcard tool grants, or tool-schema
smuggling. Atlas: `J3`, `J4`, `I3`. Threats: `MCP-T01`, `MCP-T03`, `MCP-T08`.

**Vet with:** skillseraph — pre-commit, boot.

**Fail-closed test.** Add an MCP server def with a raw-IP URL and env-credential
injection; skillseraph's `mcp_servers` category flags it and fails CI.

---

## Live MCP servers

**Category:** runtime · **Default trust:** medium · **Coverage:** strong

**Purpose.** Deployed MCP endpoints the agent connects to — the actual tool
providers answering `tools/list` and `tools/call`.

**Risk.** Dangerous tools exposed, schema over-disclosure at the anonymous lane,
rug-pull mutation after init, SSRF-capable tools, and secrets returned in tool
output. Atlas: `I1`, `I3`. Threats: `MCP-T03`, `MCP-T06`, `MCP-T07`, `MCP-T50`.

**Vet with:** mcpnuke — CI, runtime.

**Fail-closed test.** Run mcpnuke against the endpoint; a known
dangerous/exfil-capable tool produces a finding mapped to its `MCP-T` ID, and
`--generate-policy` emits a nullfield deny for it.

---

## Tool registry & schemas

**Category:** runtime · **Default trust:** medium · **Coverage:** strong

**Purpose.** The allowlist of approved tools plus their schemas that the arbiter
enforces against — it declares which tools are even eligible to be called.

**Risk.** An unregistered tool reaching upstream, schema drift / rug-pull,
over-broad wildcard registration, or credential patterns embedded in schemas.
Atlas: `I1`, `I3`. Threats: `MCP-T03`, `MCP-T50`.

**Vet with:** nullfield (registry gate) + mcpnuke (live discovery) — runtime, CI.

**Fail-closed test.** Call a tool absent from the registry; nullfield rejects at
the registry gate (`-32003`) before policy evaluation even runs.

---

## The arbiter / policy enforcement point

**Category:** runtime · **Default trust:** n/a · **Coverage:** strong

**Purpose.** The in-path decision point that evaluates every `tools/call` and
returns ALLOW / DENY / HOLD / SCOPE / BUDGET before the call reaches the tool.
This is where declared intent becomes (or is denied) real action.

**Risk.** Bypass — a tool reached without traversing the arbiter — fail-open on
controller loss, or missing enforcement so policy is advisory rather than
binding. Atlas: `F`, `I`. Threats: `MCP-T04`, `MCP-T25`.

**Vet with:** nullfield — runtime.

**Fail-closed test.** Attempt a denied tool through the sidecar (expect
`-32000`), then attempt to reach the upstream *directly*, bypassing the sidecar.
The bypass path must be blocked by network/mesh policy — the arbiter alone is
only as strong as the guarantee that all traffic routes through it.

---

## Policy files (NullfieldPolicy, AgenticFlow, CRDs)

**Category:** runtime · **Default trust:** n/a · **Coverage:** strong

**Purpose.** Declared intent that compiles to enforcement — which tool/action is
allowed, held, scoped, or denied; credential binding; and generated
network/mesh controls.

**Risk.** Overly permissive rules, a missing default-deny, tampered policy,
broad generated network/authz, or a credential bound to the wrong action.
Atlas: `F`, `J`. Threats: `MCP-T04`, `MCP-T29`.

**Vet with:** nullfield (compile-time validation, fail-closed generation) —
apply, CI.

**Fail-closed test.** Submit an `AgenticFlow` with `generatedControls` in apply
mode but a broad selector / no ports; the compiler rejects it and status reports
`Compiled=False`. Ambiguous intent fails closed rather than emitting a broad
allow.

---

## CLI / subprocess / native function-calling flows

**Category:** runtime · **Default trust:** medium · **Coverage:** partial

**Purpose.** The non-MCP tool paths — spawning `kubectl`/`terraform`, in-process
SDK calls, native LLM function-calling — i.e. transport surfaces B–E, where
identity boundaries frequently do not exist.

**Risk.** Credential inheritance across the process boundary, identity dilution
in agent chains, function-calling context leak, shell-wrap injection, and bypass
of an MCP-only arbiter entirely. Atlas: `B`, `F`, `I`. Threats: `MCP-T34`,
`MCP-T35`, `MCP-T45`, `MCP-T48`, `MCP-T49`, `MCP-T53`.

**Vet with:** camazotz (demonstrates) + mcpnuke (transport-aware probes) — eval,
runtime.

**Fail-closed test.** Run the camazotz transport B–E chain labs on hard
difficulty; the enforcement stack must block credential forwarding / identity
erasure (a passing result is an info finding, not a critical).

**Gap.** Transports B–E routinely bypass an MCP-only arbiter. Runtime
enforcement here is a known ecosystem gap — the honest reason this surface is
`partial`.

---

## Models / inference backends

**Category:** model · **Default trust:** medium · **Coverage:** strong

**Purpose.** The LLM and its serving backend (Ollama, vLLM, TGI, and similar)
that produce the agent's decisions.

**Risk.** Unauthenticated inference backend exposure, model integrity drift or
tampering, and guardrail-resistance variance across models. Atlas: `A`, `G`.
Threats: `MCP-T54`, `MCP-T55`, `MCP-T56`.

**Vet with:** stoneburner — eval.

**Fail-closed test.** Run stoneburner's adversarial and guardrail-resistance
suites plus the live infra probe; an unauthenticated backend or a changed model
digest produces a finding against the known-good baseline.

---

## Evals / benchmarks

**Category:** model · **Default trust:** n/a · **Coverage:** strong

**Purpose.** The harnesses that measure model behavior — adversarial fixtures,
red/blue capability eval, `archreview`, multi-judge consensus.

**Risk.** Eval gaming, non-deterministic pass/variance masking regressions,
single-judge bias, or fixtures drifting from live threats. Atlas: `A`, `E`.
Threats: `MCP-T56`.

**Vet with:** stoneburner — eval, CI.

**Fail-closed test.** Run a known-vulnerable fixture through the suite;
multi-judge consensus and multi-pass variance must flag it rather than pass on a
lucky run.

---

## Identity, tokens, credentials

**Category:** identity · **Default trust:** high · **Coverage:** partial

**Purpose.** How callers authenticate and how credentials reach tools — OAuth
tokens, machine identity (tbot/SPIFFE), certificates, the token vault, and
per-action credential binding.

**Risk.** Ambient broad tokens, confused deputy / replay, token theft,
credential inheritance, cross-IdP pollution, DPoP key forgery, and plaintext
cached tokens. Atlas: `F`, `K`. Threats: `MCP-T04`, `MCP-T18`, `MCP-T21`,
`MCP-T42`, `MCP-T43`, `MCP-T57`.

**Vet with:** platform (Teleport/ZITADEL issuance) + nullfield (per-action
credential binding / SCOPE) — runtime.

**Fail-closed test.** Trigger a denied tool that would need a credential and
confirm the credential was never attached (bound only to declared allowed
actions); confirm a replayed or expired token is rejected.

**Gap.** Issuance and per-action binding are covered, but end-to-end downscoping
to per-invocation least privilege *across all providers* remains partial — the
provider-scope ceiling (Slack/Atlassian/PagerDuty) is broader than any single
flow needs.

---

## Memory / RAG / state

**Category:** model · **Default trust:** high · **Coverage:** partial

**Purpose.** Durable and retrieved context an agent reads — conversation memory,
vector stores, RAG document pipelines.

**Risk.** RAG/document poisoning that hijacks the synthesizer, cross-tenant
memory leak, temporal consistency drift, and pre-auth input stored raw then
inherited by a later session. Atlas: `C`. Threats: `MCP-T11`, `MCP-T16`,
`MCP-T39`, `MCP-T52`.

**Vet with:** camazotz (Domain C labs demonstrate) — eval.

**Fail-closed test.** Run the RAG-injection lab with a poisoned document;
enforcement/inspection must catch the injected instruction before it drives a
tool call.

**Gap.** Demonstrated in camazotz, but runtime detection of poisoned *retrieved*
content is thin — no dedicated at-rest scanner for memory/RAG stores yet.

---

## Audit / observability

**Category:** infra · **Default trust:** n/a · **Coverage:** partial

**Purpose.** The decision-level record of what happened and why — audit events,
metrics, OTLP traces, the controller event stream, and detections.

**Risk.** Audit log evasion, identity dilution making sub-agents invisible in
the trail, missing decision provenance, and no attack-to-alert correlation.
Atlas: `E`. Threats: `MCP-T13`, `MCP-T22`, `MCP-T32`.

**Vet with:** nullfield (decision-level audit context) + manual (detection
catalog) — runtime.

**Fail-closed test.** Run a known attack (a camazotz lab) and assert the
corresponding audit event *and* detection fired, with rule/gate/identity present
— the purple-team correlation check.

**Gap.** nullfield emits rich decision-level audit, but a consolidated detection
catalog and attack-to-alert correlation is a roadmap gap.

---

## Automation / CI triggers

**Category:** control-plane config · **Default trust:** high · **Coverage:** strong

**Purpose.** Event-driven automation config — CI workflow triggers, agent
automations, and hooks that fire on events with write permissions.

**Risk.** Wildcard event triggers, shell exec inside automations, broad write
permissions, or a remote bootstrap on trigger. Atlas: `J3`, `J4`. Threats:
`MCP-T09`, `MCP-T14`.

**Vet with:** skillseraph — CI.

**Fail-closed test.** Add an automation with a wildcard trigger, shell exec, and
broad write scope; skillseraph's `automation_triggers` category flags it and
fails CI.
