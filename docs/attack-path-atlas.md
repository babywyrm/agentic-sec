# Attack Path Atlas

Strategic map of attack vectors across the agentic AI ecosystem. Each path is
tracked from concept through tooling coverage, with explicit gaps driving the
roadmap for all repos in the agentic-sec family.

**Purpose:** Define WHAT the ecosystem must cover. Each tool repo decides HOW.

---

## How to read this document

Each attack domain contains paths. Each path has:

| Field | Meaning |
|-------|---------|
| **ID** | Stable reference (domain letter + number) |
| **Threat** | What the attacker achieves |
| **Plane** | Which architectural layer is exploited |
| **Demo** | camazotz lab or CTF box that proves it works |
| **Scan** | mcpnuke module that detects it |
| **Block** | nullfield policy primitive that prevents it |
| **Measure** | stoneburner suite that benchmarks resistance |
| **OWASP** | Cross-reference to MCP/LLM/Web Top 10 |
| **Status** | Covered / Partial / Gap |

---

## Domain A — Agent Reasoning Attacks

The LLM's decision-making process is itself the attack surface. No network
exploitation required — the attack happens in the reasoning layer.

| ID | Threat | Technique | OWASP | Status |
|----|--------|-----------|-------|--------|
| A1 | Semantic drift | Multi-turn context manipulation gradually shifts agent behavior without any single turn triggering detection | MCP06, LLM01 | Partial |
| A2 | Plan injection | Malicious instructions in tool output alter the agent's next-step plan | MCP06, LLM01 | Covered |
| A3 | Reward hacking | Agent optimizes for proxy metric rather than true objective (e.g., marks ticket resolved without fixing) | LLM09 | Gap |
| A4 | Lookahead manipulation | Attacker structures inputs so the model's chain-of-thought leads to a desired conclusion | LLM01 | Gap |
| A5 | Metacognitive manipulation | Prompts that cause the model to doubt its own safety guidelines | LLM01 | Partial |

**Tool coverage:**

| Path | camazotz | mcpnuke | nullfield | stoneburner |
|------|----------|---------|-----------|-------------|
| A1 | T05 (cross-tool context) | behavioral drift check | maxDepth, session binding | adversarial multi-turn |
| A2 | T01/T02 labs | prompt-injection-canary | output filtering | redblue injection suite |
| A3 | — | — | HITL gate | archreview (indirect) |
| A4 | — | — | — | archreview reasoning eval |
| A5 | T56 (guardrail bypass) | inference probe | — | adversarial guardrail suite |

---

## Domain B — Multi-Agent Trust

When multiple agents or sub-agents interact, trust boundaries become attack surfaces.

| ID | Threat | Technique | OWASP | Status |
|----|--------|-----------|-------|--------|
| B1 | Orchestrator impersonation | Sub-agent crafts responses that look like orchestrator directives | MCP02 | Partial |
| B2 | Agent wormhole | Payload propagates across agent boundaries via shared context/memory | MCP10 | Partial |
| B3 | Covert channel | Agents communicate through side effects (tool outputs, timing) to bypass policy | MCP08 | Gap |
| B4 | Trust transitivity | Agent A trusts Agent B, which trusts Agent C — attacker compromises C to reach A | MCP02, MCP07 | Covered |
| B5 | Delegation depth escalation | Nested sub-agent calls accumulate privileges beyond what any single agent should hold | MCP02 | Covered |

---

## Domain C — Memory, State & Temporal Attacks

Attacks that persist across sessions or exploit stateful components (RAG, vector DBs, conversation memory).

| ID | Threat | Technique | OWASP | Status |
|----|--------|-----------|-------|--------|
| C1 | Sleeper payload | Injected content activates only when a trigger condition is met in a future session | MCP06 | Gap |
| C2 | RAG corpus poisoning | Attacker inserts documents into retrieval corpus that contain injection payloads | MCP03, MCP06 | Covered |
| C3 | Session resurrection | Expired session state replayed to inherit prior authorization context | MCP01 | Partial |
| C4 | Memory poisoning | False facts injected into agent memory persist and influence future decisions | MCP10 | Partial |
| C5 | Behavioral anchoring | Early interaction patterns lock agent into an exploitable decision framework | LLM01 | Gap |

---

## Domain D — Supply Chain & Ecosystem

Pre-deployment compromise of the agentic stack: tools, packages, configs, registries.

| ID | Threat | Technique | OWASP | Status |
|----|--------|-----------|-------|--------|
| D1 | Registry typosquatting | Malicious MCP server package with similar name to legitimate one | MCP04 | Partial |
| D2 | Dependency confusion | Internal package name collision with public registry | MCP04 | Gap |
| D3 | Manifest injection | Tool manifest (AGENTS.md, skills, MCP schema) modified to include hidden instructions | MCP03 | Covered |
| D4 | CI/CD pipeline compromise | Agent with deploy permissions manipulated into pushing malicious artifacts | MCP04 | Covered |
| D5 | Tool definition drift (rug-pull) | Tool behaves normally until trust established, then changes behavior | MCP03 | Covered |

---

## Domain E — Observability & Detection Evasion

Attacks that target the defender's ability to see and respond.

| ID | Threat | Technique | OWASP | Status |
|----|--------|-----------|-------|--------|
| E1 | Context dead zones | Agent operates in areas without telemetry coverage | MCP08 | Partial |
| E2 | Alert fatigue engineering | Flood benign alerts to mask real attack signals | MCP08 | Gap |
| E3 | Telemetry integrity | Tamper with logs/metrics to hide evidence | MCP08 | Partial |
| E4 | Attribution laundering | Use agent identity instead of user identity in audit trail | MCP08 | Covered |
| E5 | Detection timing | Execute malicious ops during known monitoring gaps (maintenance windows, batch jobs) | MCP08 | Gap |

---

## Domain F — Identity, Auth & Delegation

The authorization plane — who can do what, and how agents inherit/escalate permissions.

| ID | Threat | Technique | OWASP | Status |
|----|--------|-----------|-------|--------|
| F1 | OAuth scope laundering | Agent requests broad scope, uses narrow scope to justify the grant, then exploits the broad scope | MCP01, MCP02 | Covered |
| F2 | Ambient authority | Agent invokes tools simply because they exist in its manifest, with no per-call authorization | MCP07 | Covered |
| F3 | Confused deputy (MCP) | Tool call made with agent's credentials when it should use user's | MCP02, MCP07 | Covered |
| F4 | HITL bypass via split chain | Decompose dangerous operation into individually benign steps that each pass human approval | MCP02 | Partial |
| F5 | Token audience bypass | JWT accepted by wrong service due to missing `aud` validation | MCP01 | Covered |
| F6 | Cross-service credential forwarding | Token from Service A replayed against Service B | MCP01 | Covered |

---

## Domain G — Infrastructure & Network (K8s + AI)

Where traditional infrastructure security meets agentic workloads.

| ID | Threat | Technique | OWASP | Status |
|----|--------|-----------|-------|--------|
| G1 | Inference endpoint exposure | vLLM/Ollama API reachable without auth from untrusted pods | MCP09 | Covered |
| G2 | Pod escape from agent workload | Container breakout from agent pod to node | MCP05 | Partial |
| G3 | IRSA/workload identity abuse | Agent pod's cloud IAM role over-permissioned | MCP02 | Covered |
| G4 | NetworkPolicy gaps | Agent pod can reach internal services (metadata, etcd, other tenants) | MCP05 | Covered |
| G5 | Admission policy bypass | AI-powered admission controller fooled by crafted pod spec | MCP06 | Covered |
| G6 | SSRF via tool to cloud metadata | MCP tool fetches attacker-controlled URL that resolves to IMDS | MCP05 | Covered |
| G7 | Secrets in tool output | API keys, tokens, or creds returned in tool response without DLP | MCP10 | Covered |

---

## Domain H — Human-in-the-Loop Exploitation

Attacks that target the human oversight layer rather than technical controls.

| ID | Threat | Technique | OWASP | Status |
|----|--------|-----------|-------|--------|
| H1 | Approval fatigue | High volume of benign requests conditions human to auto-approve | — | Gap |
| H2 | Semantic deception | Request appears benign in summary but has dangerous implications | MCP06 | Partial |
| H3 | Timing attack | Submit dangerous request during known low-attention periods | — | Gap |
| H4 | Information asymmetry | Agent has context that human reviewer doesn't, making informed decision impossible | — | Gap |
| H5 | Split action chain | Multi-step operation where each step looks safe individually | MCP02 | Partial |

---

## Domain I — MCP Protocol Specifics

Attack vectors unique to the MCP wire protocol and server lifecycle.

| ID | Threat | Technique | OWASP | Status |
|----|--------|-----------|-------|--------|
| I1 | Direct prompt injection | User input → tool argument → LLM context without sanitization | MCP06 | Covered |
| I2 | Indirect prompt injection | Fetched content (web, DB, file) contains injection payload | MCP06 | Covered |
| I3 | Tool schema smuggling | Hidden instructions in tool description/parameter names/examples | MCP03 | Covered |
| I4 | Cross-tool context poisoning | Output from Tool A poisons the context for Tool B's invocation | MCP10 | Covered |
| I5 | Shadow MCP server | Unauthorized server accepts connections on expected endpoint | MCP09 | Covered |
| I6 | Callback/webhook persistence | Tool registers a callback that outlives the session | MCP09 | Covered |
| I7 | Schema over-disclosure | Tool exposes internal structure/capabilities to unauthenticated clients | MCP10 | Covered |
| I8 | Resource exhaustion via fan-out | Recursive or parallel tool calls consume unbounded resources | MCP05 | Covered |

---

## Domain J — AGENTS.md, Skills, Rules & Automation Config

Attacks targeting the configuration layer that defines agent behavior.

| ID | Threat | Technique | OWASP | Status |
|----|--------|-----------|-------|--------|
| J1 | Rule injection | Malicious rule added to .cursor/rules or AGENTS.md that persists across sessions | MCP09 | Gap |
| J2 | Skill poisoning | Modified SKILL.md with hidden instructions executed on invocation | MCP03 | Gap |
| J3 | Automation trigger abuse | Crafted event triggers an automation with unintended scope | MCP09 | Gap |
| J4 | Hook manipulation | Git hook or agent hook modified to execute on sensitive events | MCP04 | Gap |
| J5 | Config inheritance escalation | Child workspace inherits overly permissive parent config | MCP02 | Gap |

---

## Domain K — Zero Trust & Cryptographic

Failures in the trust verification and cryptographic layers.

| ID | Threat | Technique | OWASP | Status |
|----|--------|-----------|-------|--------|
| K1 | mTLS bypass | Agent-to-service connection without mutual authentication | MCP07 | Partial |
| K2 | SPIFFE ID spoofing | Workload claims wrong identity in mesh | MCP07 | Partial |
| K3 | DPoP key extraction | Proof-of-possession key leaked enabling token replay | MCP01 | Covered |
| K4 | Certificate pinning absence | Agent connects to impersonated endpoint | MCP07 | Partial |
| K5 | Token downgrade | Force fallback from strong auth to weaker mechanism | MCP01 | Gap |

---

## Coverage Summary

| Domain | Paths | Covered | Partial | Gap |
|--------|-------|---------|---------|-----|
| A — Reasoning | 5 | 1 | 2 | 2 |
| B — Multi-Agent | 5 | 2 | 2 | 1 |
| C — Memory/Temporal | 5 | 1 | 2 | 2 |
| D — Supply Chain | 5 | 3 | 1 | 1 |
| E — Observability | 5 | 1 | 2 | 2 |
| F — Identity/Auth | 6 | 5 | 1 | 0 |
| G — Infrastructure | 7 | 6 | 1 | 0 |
| H — HITL | 5 | 0 | 2 | 3 |
| I — MCP Protocol | 8 | 8 | 0 | 0 |
| J — Config/Automation | 5 | 0 | 0 | 5 |
| K — Zero Trust | 5 | 1 | 3 | 1 |
| **TOTAL** | **61** | **28** | **16** | **17** |

**46% covered, 26% partial, 28% gap** — the gaps are concentrated in:
- Reasoning manipulation (A3, A4)
- HITL exploitation (H1–H4)
- Config/Automation poisoning (J1–J5)
- Temporal/sleeper attacks (C1, C5)
- Observability evasion (E2, E5)

---

## Cross-Reference: OWASP MCP Top 10

| OWASP MCP | Atlas Domains | Primary paths |
|-----------|---------------|---------------|
| MCP01 Token Mismanagement | F, K | F5, F6, K3, K5 |
| MCP02 Privilege Escalation | B, F, G | B4, B5, F1, F3, F4, G3 |
| MCP03 Tool Poisoning | C, D, I, J | C2, D3, D5, I3, J2 |
| MCP04 Supply Chain | D, J | D1, D2, D4, J4 |
| MCP05 Command Injection | G, I | G2, G4, G6, I8 |
| MCP06 Prompt Injection | A, C, H, I | A1, A2, A5, C1, H2, I1, I2 |
| MCP07 Insufficient Auth | F, K | F2, F3, K1, K2, K4 |
| MCP08 Lack of Audit | E | E1, E2, E3, E4, E5 |
| MCP09 Shadow Servers | I, J | I5, I6, J1, J3 |
| MCP10 Context Leakage | B, C, G, I | B2, C4, G7, I4, I7 |

---

## What this drives (per repo)

| Repo | Atlas tells it... |
|------|-------------------|
| **camazotz** | Which labs to build next (Domain H, J have zero labs) |
| **mcpnuke** | Which scanner modules are missing (reasoning drift, config injection) |
| **nullfield** | Which policy primitives need design (HITL fatigue guards, config integrity) |
| **stoneburner** | Which benchmark suites to add (reasoning manipulation, memory persistence) |
| **agentic-sec** | Where walkthroughs and campaigns are needed |

---

## Versioning

| Version | Date | Change |
|---------|------|--------|
| 1.0 | 2026-06-20 | Initial atlas — 11 domains, 61 paths |
