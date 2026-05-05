# Ecosystem Architecture — Defending MCP at Scale

This document is for security engineers evaluating how to secure Model Context
Protocol (MCP) tool execution in production Kubernetes environments. It explains
the architecture, the defense layers, how to test them, and what to present to
your security review board.

> **Read first:** [The Identity Flow Framework](identity-flows.md) is the
> foundational lens this document is written through. The "defense layers"
> below correspond to the lane × transport matrix defined there: nullfield is
> the per‑cell policy enforcer, Teleport handles Lane 3 (and Lane 4
> partially), ZITADEL handles Lanes 1 and 2, and mcpnuke validates every
> cell.

---

## The Problem

MCP connects AI models to real tools — database queries, deployments, credential
brokers, webhook registrations. Every `tools/call` is a function invocation with
side effects, triggered by an LLM that cannot be trusted to make authorization
decisions.

The attack surface is not theoretical. Camazotz demonstrates 39 distinct
vulnerability patterns spanning five agentic-identity lanes and five transport
surfaces (A=MCP, B=Direct API, C=in-process SDK, D=subprocess, E=native LLM
function-calling — see [ADR 0001](https://github.com/babywyrm/camazotz/blob/main/docs/adr/0001-five-transport-taxonomy.md))
— from prompt injection that triggers secret exfiltration, to
confused-deputy attacks where the AI grants admin access because the attacker
wrote a convincing justification. These attacks work because:

1. **LLM guardrails are advisory, not enforceable.** The model can warn about a
   dangerous action in its reasoning while the underlying tool logic executes it.
2. **Static API keys provide no identity.** You cannot distinguish a human
   operator from a compromised agent from a replayed token.
3. **Tool execution has no policy layer.** Without an arbiter, any registered
   tool call is forwarded to the upstream server unconditionally.

The defense stack described here addresses all three.

---

## The Defense Layers

### Layer 1: nullfield — The Arbiter

[nullfield](https://github.com/babywyrm/nullfield) is a sidecar proxy that
intercepts every MCP `tools/call` and makes a decision before forwarding. Five
actions define what nullfield can do with a tool call:

| Action | What Happens | Example |
|--------|-------------|---------|
| **ALLOW** | Forward immediately | Read-only status checks |
| **DENY** | Reject immediately | Exfiltration tools, unregistered tools |
| **HOLD** | Park for human approval | Production deployments, agent delegation |
| **SCOPE** | Allow but modify in transit | Strip secrets from args, redact response PII |
| **BUDGET** | Allow but enforce quotas | Per-identity call limits, token cost caps |

These compose. A single request can be budget-checked, scoped, held for approval,
then forwarded. The policy is expressed in YAML (or as a Kubernetes CRD) and
evaluated top-to-bottom, first match wins, default deny.

**Where it sits:**

```
MCP Client → nullfield (:9090) → brain-gateway (:8080)
                ↓
         decision chain:
         identity → registry → integrity → circuit → policy → budget → audit
```

nullfield adds ~2ms to the request path. It runs as a sidecar container, a
standalone gateway, or is auto-injected via a mutating admission webhook
(`nullfield.io/inject: "true"`).

**What it solves:** Even if the LLM is compromised or manipulated, the policy
layer enforces hard boundaries. The AI cannot override a DENY rule.

### Layer 2: Teleport — Machine Identity

[Teleport](https://goteleport.com) provides cryptographic identity for agents
and workloads. Instead of static API keys or long-lived service account tokens,
agents authenticate with short-lived X.509 certificates issued by Teleport's
auth service.

**How it works:**

1. `tbot` runs alongside the agent (as a sidecar or standalone deployment).
2. tbot authenticates to the Teleport auth service using its Kubernetes
   ServiceAccount JWT — no shared secrets.
3. Teleport issues a short-lived certificate (1-hour TTL, auto-renewed every
   20 minutes) that carries the agent's identity and roles.
4. The agent uses this certificate to access K8s resources (via kubeconfig) or
   MCP servers (via Teleport App Access).

**What it solves:** Every agent action is tied to a cryptographic identity.
Certificates expire automatically. Roles are enforced server-side. The audit
trail shows exactly which bot accessed which resource and when.

**How it complements nullfield:** Teleport handles *who can connect*. nullfield
handles *what they can do once connected*. Teleport says "this agent has the
`agent-mcp` role and can reach the MCP server." nullfield says "this agent can
call `cost.check_usage` but not `secrets.leak_config`, and it's limited to 20
calls per hour."

### Layer 3: mcpnuke — Automated Validation

[mcpnuke](https://github.com/babywyrm/mcpnuke) is a security scanner purpose-built
for MCP servers. It performs three types of analysis:

**Static analysis** — examines tool definitions, schemas, and metadata for
dangerous patterns (credential parameters, execution capabilities, webhook
registration, supply chain risks) without calling any tools.

**Behavioral probes** — calls tools with safe payloads and analyzes responses
for injection vectors, credential leakage, temporal inconsistencies, and
cross-tool manipulation.

**Infrastructure checks** — probes the surrounding infrastructure for
misconfigurations. The Teleport-aware checks discover proxy endpoints, flag
self-signed certificates, test for unauthenticated app enumeration, check
tbot credential exposure, and flag over-privileged bot service accounts.

**Exploit chain automation** — for environments running camazotz with the
Teleport labs, mcpnuke chains the lab tools into complete attack sequences:

| Chain | Steps | What It Tests |
|-------|-------|---------------|
| Bot identity theft | Read tbot secret → replay cert → check session binding | MCP-T18: credential theft and replay |
| Role escalation | Get roles → request escalation → privileged operation | MCP-T28: RBAC bypass via social engineering |
| Cert replay | Get expired cert → replay in grace window → check detection | MCP-T19: short-lived cert revocation gap |

Each chain reports whether the attack succeeded (finding) or the defense held
(info). On easy difficulty, attacks succeed. On hard difficulty, nullfield's
session binding, HOLD gates, and replay detection block them.

---

## How the Layers Interact

```mermaid
flowchart LR
  subgraph Attackers["Attack side"]
    BOT["Agent / Bot<br/>(tbot cert)"]
    MCPNUKE["mcpnuke scanner<br/>(outside-in)"]
  end

  subgraph Cluster["Kubernetes cluster"]
    direction TB
    TELEPORT["<b>Teleport Proxy</b> :443<br/>identity layer"]
    K8S["K8s API<br/>(RBAC: agent-readonly)"]
    NF["<b>nullfield sidecar</b> :9090<br/>identity → registry → integrity →<br/>circuit → policy → budget → audit"]
    GW["<b>brain-gateway</b> :8080<br/>39 vulnerable MCP labs<br/>(5 lanes × 5 transports)"]
  end

  BOT -->|short-lived cert| TELEPORT
  TELEPORT -->|kubeconfig| K8S
  TELEPORT -->|MCP App Access| NF
  NF -->|ALLOW / SCOPE / BUDGET forwarded| GW
  NF -.->|DENY / HOLD queued| HOLDQ["human approval queue"]
  MCPNUKE -->|scan| TELEPORT
  MCPNUKE -->|scan tools/list + probes| GW

  classDef identity fill:#60a5fa,stroke:#1e3a8a,color:#000;
  classDef policy   fill:#a78bfa,stroke:#4c1d95,color:#000;
  classDef target   fill:#fb923c,stroke:#7c2d12,color:#000;
  classDef scanner  fill:#34d399,stroke:#064e3b,color:#000;
  class TELEPORT,K8S identity;
  class NF,HOLDQ policy;
  class GW target;
  class MCPNUKE scanner;
```

The key insight: **defense in depth is testable**. You deploy nullfield and
Teleport as the defense. You deploy camazotz as the vulnerable target. You run
mcpnuke to prove the defenses work. If mcpnuke's exploit chains produce
CRITICAL findings on hard difficulty, your policy has gaps. If they produce
INFO findings ("defense held"), you're in good shape.

### The Lane View — `/lanes` UI + `/api/lanes` JSON contract

Camazotz ships two parallel views over the 39 labs: `/threat-map` groups
by attack category, **`/lanes` groups by identity lane** (Lane 1 Human
Direct → Lane 5 Anonymous, with the per-lane flow diagram, default
nullfield action, covering mcpnuke checks, and coverage gaps inline).
The same data is exposed as a stable machine-readable contract at
`GET /api/lanes` (schema `v1`) and is the surface
`mcpnuke --coverage-report <camazotz-url>` consumes to emit cross-project
coverage reports. The lane slugs (`human-direct`, `delegated`, `machine`,
`chain`, `anonymous`) and transport codes (`A`–`E`) in that response are
the ecosystem's shared vocabulary — nullfield policies key on them, and
mcpnuke findings carry them as fields. If they ever change in camazotz,
the other two repos must move in lockstep.

---

## Per-Project Coverage Scorecard

What each project covers today, and what it deliberately leaves to the others.
This is the honest boundary of the ecosystem as of 2026-04-26.

| Project | Covers | Does not cover | Source of truth |
|---------|--------|----------------|-----------------|
| **[camazotz](https://github.com/babywyrm/camazotz)** | 39 labs across all 5 identity lanes and 5 transport surfaces (A=MCP, B=Direct API, C=in-process SDK, D=subprocess, E=native LLM function-calling). Parallel browsing via `/threat-map` (by attack category) and `/lanes` (by identity flow). | Runtime enforcement, live detection of attacker traffic, policy generation. Camazotz is the *target*, not a defense. | `GET /api/lanes` schema v1, `scenario.yaml` per lab |
| **[nullfield](https://github.com/babywyrm/nullfield)** | Per-tool-call policy enforcement: ALLOW / DENY / HOLD / SCOPE / BUDGET. Identity verification (JWT/cert). Session binding. Response redaction. Budget accounting. | Scanning for new vulnerabilities, generating initial policies from scratch, IDP issuance, long-term audit storage. | `NullfieldPolicy` CRD; per-lane starter templates (spec 2026-04-26) |
| **[mcpnuke](https://github.com/babywyrm/mcpnuke)** | Static, behavioral, infrastructure, and exploit-chain scanning of MCP servers. Policy recommendation (`--generate-policy`). Teleport-aware checks. Per-lane reporting (spec 2026-04-26). | Runtime request blocking (that's nullfield's job). Identity issuance. Deployment. | Finding dataclass; `--json` output |
| **[agentic-sec](https://github.com/babywyrm/agentic-sec)** | The shared vocabulary — lane slugs, transport codes, threat taxonomy, golden-path architecture. Cross-project walkthroughs. | Any implementation. It is strictly documentation. | `docs/identity-flows.md` |

**Coverage gaps acknowledged in the current corpus** (surfaced by
camazotz `/api/lanes` as machine-readable `gaps`):

- Lane 1 (Human Direct) — no Transport C (SDK) lab yet
- Lane 2 (Delegated) — no Transport C lab yet
- Lane 3 (Machine) — no Transport B (direct API) lab yet
- Lane 4 (Agent → Agent) — no Transport B or C lab yet
- Lane 5 (Anonymous) — has no transport notion by design (pre-auth)

These aren't failures; they are the honest boundary of what the lab corpus
teaches and the concrete next additions as the ecosystem grows.

---

## Roadmap — How This Grows

Three horizons, committed in decreasing order of near-term certainty.

### Shipped

- ✅ nullfield per-lane policy templates + three new primitives (`identity.requireActChain`, `delegation.maxDepth`, `identity.audienceMustNarrow`) — *2026-04-26*
- ✅ mcpnuke `--by-lane` and `--coverage-report` — *2026-04-26*
- ✅ nullfield CRD watcher + active-policy bridge — *2026-04-27*
- ✅ Five-transport taxonomy (D = subprocess, E = native LLM function-calling) ratified in camazotz ADR 0001 — *2026-04-28*
- ✅ `sdk_tamper_lab` (Lane 1 / Transport C), `subprocess_lab` (Lane 3 / Transport D), `function_calling_lab` (Lane 2 / Transport E) — *2026-04-28/29*
- ✅ mcpnuke `--coverage N`, `--diff-baseline`, `--profile` — *2026-05-03*
- ✅ Campaign scenario system (`make campaign SCENARIO=...`) + four pre-authored NullfieldPolicy CRDs — *2026-05-03*

### Near-term (actively worked)

- Fill remaining baseline transport gaps — Lane 2 / Transport C, Lane 3 / Transport B, Lane 4 / Transport B
- Walkthrough: "Building a Lane 4 defense from scratch" using `delegation.maxDepth` against `delegation_depth_lab` and `delegation_chain_lab`
- Lane 4 transport widening — agent chains today are all MCP (Transport A); D and E variants would model real LangChain / OpenAI Assistants chains

### Future (revisit when the vocabulary drifts)

- Central machine-readable taxonomy at `agentic-sec/docs/taxonomy/lanes.yaml` — only worth the cross-repo dependency if camazotz, nullfield, and mcpnuke start to drift from each other
- Per-lane rate-limit primitives in nullfield (distinct from global `maxCallsPerMinute`)
- mcpnuke `--watch` mode producing continuous lane-coverage deltas against a long-running camazotz target
- Broader IdP support in camazotz labs — Okta and Auth0 alongside ZITADEL to widen Lane 1/2 coverage

---

## The Teleport Labs — What They Teach

Three camazotz labs specifically test Teleport machine identity patterns:

### Bot Identity Theft (`bot_identity_theft_lab`, MCP-T18)

**Attack:** A tbot agent writes short-lived certificates to a Kubernetes Secret.
If that secret is readable by other pods (misconfigured RBAC), an attacker
extracts the certificate and replays it to access MCP tools as the bot.

**What varies by difficulty:**
- Easy: Secret is mounted into all pods. Cert replay succeeds. Flag captured.
- Medium: Secret requires RBAC exploit. Cert replay succeeds if serial matches.
- Hard: Secret is inaccessible. Even if obtained, nullfield session binding
  detects the identity mismatch and denies the call.

**Golden path defense:** Scope tbot secrets to specific pods via RBAC.
Enable nullfield `integrity.bindToSession` to catch identity swaps.

### Role Escalation (`teleport_role_escalation_lab`, MCP-T28)

**Attack:** The bot has `agent-readonly` but discovers an MCP tool that modifies
role assignments. By crafting a convincing justification, it social-engineers
the LLM into approving an escalation to `agent-ops`.

**What varies by difficulty:**
- Easy: LLM approves any justification. Escalation succeeds. Privileged op executes.
- Medium: LLM requires an approved incident ticket. Social engineering with
  ticket reference succeeds.
- Hard: All escalation requests are held for human approval via nullfield's
  HOLD action. The bot cannot self-escalate.

**Golden path defense:** Never expose role modification as a tool. Use nullfield
HOLD on any tool that changes permissions. Teleport CE roles are static — use
Enterprise access requests for just-in-time elevation.

### Certificate Replay (`cert_replay_lab`, MCP-T19)

**Attack:** A short-lived certificate has expired, but clock skew between the
proxy and the application creates a grace window. The attacker replays the
expired cert within this window.

**What varies by difficulty:**
- Easy: Gateway accepts expired certs unconditionally. Replay succeeds.
- Medium: 30-second grace window. Certs expired < 30s ago are accepted.
- Hard: Expired certs rejected immediately. Replay detection flags the reused
  cert ID.

**Golden path defense:** Strict NTP sync across all nodes. Enable nullfield
`integrity.detectReplay` to catch reused credential identifiers. Short cert
TTLs (1 hour) limit the replay window.

---

## For Your Security Review

When presenting this to your architecture review board or CISO:

**The threat model:** MCP tool execution is remote procedure invocation
triggered by an AI. The AI is not a security boundary — it can be manipulated
by prompt injection, confused-deputy attacks, and social engineering. Every
tool call needs an independent policy decision.

**The defense:** nullfield provides that policy layer (five actions, YAML-based,
CRD-native). Teleport provides the identity layer (short-lived certs, no static
secrets, full audit). Together they implement the golden path: every request
carries identity, every tool is registered and scoped, every secret lives in a
secret manager, and the AI's output is never trusted as authorization.

**The validation:** camazotz provides 39 intentionally vulnerable labs
covering every OWASP MCP Top 10 risk and every one of the five
agentic-identity lanes. mcpnuke automates the attack sequences and
reports whether your defenses hold. Run mcpnuke on hard difficulty — if the
exploit chains fail and defenses hold, your golden path is working.

**What remains manual:** policy authoring (deciding which tools get ALLOW vs
HOLD vs DENY), role design (which agents get which Teleport roles), and
incident response runbooks (what to do when mcpnuke finds a gap).

---

## Getting Started

| Goal | Start Here |
|------|-----------|
| Understand the vulnerability patterns | [Camazotz Quick Start](https://github.com/babywyrm/camazotz/blob/main/QUICKSTART.md) — run the labs locally |
| Add the policy layer | [nullfield README](https://github.com/babywyrm/nullfield) — deploy as sidecar |
| Add machine identity | [Teleport Setup](teleport/setup.md) — step-by-step Teleport integration |
| Scan and validate | [mcpnuke README](https://github.com/babywyrm/mcpnuke) — `mcpnuke --targets http://localhost:8080/mcp` |
| Production architecture | [Golden Path v3](golden-path.md) — the complete security spec |
