# Ecosystem Architecture — Defending MCP at Scale

This document is for security engineers evaluating how to secure Model Context
Protocol (MCP) tool execution in production Kubernetes environments. It explains
the architecture, the defense layers, how to test them, and what to present to
your security review board.

---

## The Problem

MCP connects AI models to real tools — database queries, deployments, credential
brokers, webhook registrations. Every `tools/call` is a function invocation with
side effects, triggered by an LLM that cannot be trusted to make authorization
decisions.

The attack surface is not theoretical. Camazotz demonstrates 28 distinct
vulnerability patterns — from prompt injection that triggers secret exfiltration,
to confused-deputy attacks where the AI grants admin access because the attacker
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
| Bot identity theft | Read tbot secret → replay cert → check session binding | MCP-T04: credential theft and replay |
| Role escalation | Get roles → request escalation → privileged operation | MCP-T20: RBAC bypass via social engineering |
| Cert replay | Get expired cert → replay in grace window → check detection | MCP-T26: short-lived cert revocation gap |

Each chain reports whether the attack succeeded (finding) or the defense held
(info). On easy difficulty, attacks succeed. On hard difficulty, nullfield's
session binding, HOLD gates, and replay detection block them.

---

## How the Layers Interact

```
                     ┌──────────────────────────────────────────────┐
                     │            Kubernetes Cluster                │
                     │                                              │
  Agent/Bot ────────▶│  Teleport Proxy (:443)                       │
  (with tbot cert)   │       │                                      │
                     │       ├── K8s access (kubeconfig)            │
                     │       │   └── RBAC: agent-readonly           │
                     │       │                                      │
                     │       └── MCP access (App Access agent)      │
                     │           └── Teleport role: agent-mcp       │
                     │               └── Tool filter: cost.*,audit.*│
                     │                   │                          │
                     │                   ▼                          │
                     │           nullfield sidecar (:9090)          │
                     │           ├── Identity: verify cert/JWT      │
                     │           ├── Registry: tool registered?     │
                     │           ├── Policy: ALLOW/DENY/HOLD/SCOPE  │
                     │           ├── Budget: within quota?          │
                     │           └── Audit: structured log          │
                     │                   │                          │
                     │                   ▼                          │
                     │           brain-gateway (:8080)              │
                     │           └── 28 vulnerable MCP labs         │
                     │                                              │
  mcpnuke ──────────▶│  Scans both Teleport infra + MCP tools       │
  (scanner)          │  Reports findings + exploit chain results    │
                     └──────────────────────────────────────────────┘
```

The key insight: **defense in depth is testable**. You deploy nullfield and
Teleport as the defense. You deploy camazotz as the vulnerable target. You run
mcpnuke to prove the defenses work. If mcpnuke's exploit chains produce
CRITICAL findings on hard difficulty, your policy has gaps. If they produce
INFO findings ("defense held"), you're in good shape.

---

## The Teleport Labs — What They Teach

Three camazotz labs specifically test Teleport machine identity patterns:

### Bot Identity Theft (`bot_identity_theft_lab`, MCP-T04)

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

### Role Escalation (`teleport_role_escalation_lab`, MCP-T20)

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

### Certificate Replay (`cert_replay_lab`, MCP-T26)

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

**The validation:** camazotz provides 28 intentionally vulnerable labs covering
every OWASP MCP Top 10 risk. mcpnuke automates the attack sequences and
reports whether your defenses hold. Run mcpnuke on hard difficulty — if the
exploit chains fail and defenses hold, your golden path is working.

**What remains manual:** policy authoring (deciding which tools get ALLOW vs
HOLD vs DENY), role design (which agents get which Teleport roles), and
incident response runbooks (what to do when mcpnuke finds a gap).

---

## Getting Started

| Goal | Start Here |
|------|-----------|
| Understand the vulnerability patterns | [Camazotz Quick Start](../QUICKSTART.md) — run the labs locally |
| Add the policy layer | [nullfield README](https://github.com/babywyrm/nullfield) — deploy as sidecar |
| Add machine identity | [integrations/teleport/](../integrations/teleport/) — step-by-step Teleport setup |
| Scan and validate | [mcpnuke README](https://github.com/babywyrm/mcpnuke) — `mcpnuke --targets http://localhost:8080/mcp` |
| Production architecture | [Golden Path v3](mcp-at-scale-golden-path.md) — the complete security spec |
