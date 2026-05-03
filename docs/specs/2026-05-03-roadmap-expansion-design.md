# Design Spec: agentic-sec Roadmap Expansion
**Date:** 2026-05-03  
**Status:** Approved  
**Author:** tms + team

---

## North Star

agentic-sec is a **teaching platform first**. The toolchain (mcpnuke, nullfield, camazotz) grows out of pedagogy — it exists to make the teaching real and verifiable. The ecosystem coherence between the three repos *is* the product: a closed-loop reference architecture that demonstrates how to measure and enforce agentic security at every layer.

**Primary learner:** Security practitioners who know offensive/defensive security and are new to MCP and agentic AI (80%). Secondary: developers building agentic apps who don't yet think in attack surfaces (10%), CTF/challenge players (10%).

**Success definition:** A practitioner leaves with the MCP/agentic threat model internalized well enough to threat-model their own agentic deployment from first principles, and hands-on experience that reinforces the conceptual model.

**On-ramp philosophy:** Polish what exists. The platform is for practitioners who can install Docker and know what a JWT is. We are not building a browser-based experience. We are adding a better door to a house that is already well-built.

---

## Core Gap

Practitioners arrive with strong REST API / auth / cloud security instincts. MCP and agentic patterns are 1-2 year old RFCs — the security conventions haven't settled yet. The platform currently doesn't explicitly bridge from what practitioners already know to what's new and different. Every practitioner has to reconstruct that mental model themselves from 7 walkthroughs and multiple reference docs.

The highest-leverage item is a single "bridge" document that does that translation work once, for everyone.

---

## Phase 1 — The Bridge (Near-term, Highest Priority)

### 1a. `docs/bridge.md` — New Document

**Title:** "MCP Security for the Security Practitioner" (or equivalent)

**Purpose:** The canonical first read for any security practitioner. Does the mental model transfer work that currently doesn't exist in one place. Links to everything else rather than duplicating it.

**Structure:**

1. **Protocol context** (2 paragraphs) — What MCP actually specifies: tool registration, JSON-RPC call/response. What it deliberately leaves to implementations: auth, transport, identity. Why those gaps are the attack surface. Frame: "This is a 2024 RFC, not a 20-year-old standard — the security conventions are still forming."

2. **Your mental model, audited** — A table: *What you already know* | *Does it transfer to MCP/agentic?* | *What's different*. Rows:
   - REST authentication → partially (auth exists but the caller may be an AI model, not a human)
   - Input validation → transfers but the attacker is often the LLM, not the end user
   - SSRF → transfers and gets significantly worse (the AI will follow any URL in its context)
   - JWT audience checks → transfers but multi-agent delegation chains break audience assumptions
   - OWASP API Top 10 → explicit row-by-row mapping to OWASP MCP Top 10
   - Output sanitization → new concern (tool output poisons downstream LLM context)

3. **The surface map** — Five transport surfaces (A–E) tied to real-world runtimes practitioners will encounter, not abstract codes:
   - **Transport A** — MCP JSON-RPC (Claude Desktop, any MCP client, camazotz)
   - **Transport B** — Direct HTTP API (raw REST calls into a tool server, no MCP layer)
   - **Transport C** — In-process SDK (LangChain `@tool` decorators, Anthropic SDK, OpenAI function specs in Python)
   - **Transport D** — Subprocess/CLI (shell-calling agents, bash tool use, agent-driven CLI pipelines)
   - **Transport E** — Native LLM function-calling (OpenAI `function_call`, Claude `tool_use` outside MCP protocol)

4. **The identity problem** — Why the five identity lanes matter and why they have no analogue in REST API security. Who is actually calling the tool? One concrete attack example per lane in two sentences each:
   - Lane 1 (Human Direct): your OAuth token, but the AI decides how to use it
   - Lane 2 (Delegated): human authorized an agent — the agent is now the caller
   - Lane 3 (Machine): no human in the loop, certificate-based machine identity
   - Lane 4 (Agent→Agent): your trust delegation is 3 hops deep; who authorized the last hop?
   - Lane 5 (Anonymous): no identity claim at all — the default for most MCP deployments today

5. **Where to go next** — Decision tree linking into existing content:
   ```
   New to MCP?         → Start here (you're reading it)
   Want to attack?     → Walkthrough 1: The Attack
   Want to defend?     → Walkthrough 2: The Defense
   Want the full loop? → Walkthrough 5: Live Feedback Loop
   Deploying to prod?  → docs/golden-path.md
   Full curriculum?    → docs/learning-path.md
   ```

**Constraint:** Does NOT replace or duplicate `identity-flows.md`, `ecosystem.md`, or any existing doc. Links to them. This is the door, not the house.

---

### 1b. README.md — "Start Here" Prepend (Additive Edit)

Add a "Start Here" block as the very first section of the README, before all existing content. ~10 lines. Two sentences of framing + the decision tree from `bridge.md`. All existing README content (architecture diagram, project table, deep dives, quick starts, roadmap) stays completely unchanged below it.

**What the block looks like:**

```markdown
## Start Here

MCP and agentic AI patterns are new — the security conventions are still forming. 
If you know security but are new to this space, start with the bridge document 
before diving into the architecture.

| I want to... | Start here |
|---|---|
| Understand how MCP security differs from API security | [`docs/bridge.md`](docs/bridge.md) |
| Attack a vulnerable MCP server | [Walkthrough 1 — The Attack](docs/walkthroughs/attack.md) |
| Defend with policy | [Walkthrough 2 — The Defense](docs/walkthroughs/defense.md) |
| Run the full scan→enforce→validate loop | [Walkthrough 5 — Live Feedback Loop](docs/walkthroughs/live-loop.md) |
| Deploy to production securely | [Golden Path](docs/golden-path.md) |
| Follow a full learning curriculum | [`docs/learning-path.md`](docs/learning-path.md) |
```

---

### 1c. `docs/learning-path.md` — New Document

Three structured learning tracks with explicit prerequisites, time estimates, and success criteria. Points entirely to existing docs/walkthroughs — no new content required to implement this.

**Three tracks:**

| Track | Audience | Path | Time | You can do when done |
|-------|----------|------|------|----------------------|
| **Red Team** | Offensive practitioners | bridge.md → Walkthrough 1 → Walkthrough 6 (Delegation Chains) → Walkthrough 4 (AI Scanning) → all 35 labs at hard | ~4h | Enumerate and exploit any MCP server's attack surface; understand multi-agent chain attacks |
| **Blue Team** | Defenders / policy authors | bridge.md → Walkthrough 2 → Walkthrough 3 (Practice) → nullfield quick ref → golden-path.md | ~3h | Write production-grade nullfield policy; threat-model any agentic deployment |
| **Full Loop** | Platform / security engineers | bridge.md → Walkthrough 7 (Flow Types) → Walkthrough 5 (Live Loop) → Deployment Guide → feedback-loop.md | ~3h | Run the complete scan→enforce→validate cycle against any MCP target in any environment |

---

## Phase 2 — Grid Expansion (Near-term, After Phase 1)

Fills the real-world framework gap in the 5×5 lane×transport matrix. Two new labs in camazotz; one new walkthrough in agentic-sec.

### 2a. `langchain_tool_lab` (camazotz)

- **Transport:** C (in-process SDK)
- **Lane:** 2 (Human→Agent delegated)
- **Threat:** MCP-T02 / prompt injection via tool description field in LangChain-style `@tool` decorator
- **Attack path:** Attacker controls tool description; injected directive hijacks the agent's plan mid-chain
- **Easy:** No sanitization — injection directive in description is executed faithfully
- **Medium:** Basic keyword filtering — bypassable with encoding
- **Hard:** Schema validation + output SCOPE rule strips unrecognized fields; injection has no effect
- **Why this lab:** "LangChain security" is the most-searched real-world equivalent of the MCP prompt injection problem. Names the framework explicitly.

### 2b. `function_call_injection_lab` (camazotz)

- **Transport:** E (native LLM function-calling)
- **Lane:** 1 (Human Direct)
- **Threat:** MCP-T01 / injection via function name + parameter description schema fields (OpenAI `function_call` / Claude `tool_use`)
- **Attack path:** Function name or parameter `description` field carries injection payload; LLM executes it as instruction
- **Easy:** Raw schema passed through — injection executes
- **Medium:** Name/description length limits — timing-based bypass available
- **Hard:** Strict allowlist on function name format + argument schema validation; injection surface closed
- **Why this lab:** "OpenAI function calling security" and "Claude tool_use injection" are the Transport E equivalent of MCP-T01. Names the protocol explicitly.

### 2c. Walkthrough 8 — "Beyond MCP: Tool Invocation Across Frameworks" (agentic-sec)

A doc-only walkthrough (no new infrastructure). Maps the five transport surfaces to five real-world framework examples. Shows the same class of attack (tool description injection) manifesting differently across each transport. Answers "how does my knowledge from the labs transfer to what I'll encounter in a LangChain codebase, an OpenAI assistant, or a CLI agent?"

No new code or labs required — references existing labs and existing framework docs for each transport.

---

## Phase 3 — Ecosystem Reach (Medium/Future Horizon)

Captured for roadmap, **not in scope for the current sprint.**

### 3a. Lab Contribution Template (Medium-term)

- `camazotz_modules/_template/` — skeleton lab module with inline comments
- `CONTRIBUTING.md` — step-by-step lab authoring guide: directory structure, `LabModule` base class contract, threat ID mapping, difficulty level requirements, required test file pattern
- The eight unit test files written in the 2026-05 testing sprint are the implicit spec for "what a well-tested lab looks like"
- Prerequisite: Phase 1 complete (the bridge doc defines the conceptual framework contributors need)

### 3b. GitHub Action: `mcpnuke-scan` (Medium-term)

- Reusable workflow: runs `mcpnuke --fast --no-invoke --json findings.json` against a configurable URL on every PR
- Posts finding summary as PR comment (finding count, severity breakdown, new findings vs baseline)
- Two-line adoption for any team building an MCP server
- This is the primary "B — developer-facing" wedge: puts the scanner where developers already live

### 3c. Machine-Readable Taxonomy (Future)

- `agentic-sec/taxonomy/lanes.yaml` + `threats.yaml`
- Single source of truth for lane slugs, transport codes, threat IDs
- Only worth doing if drift between camazotz/mcpnuke/nullfield vocabulary becomes a real maintenance problem
- The coherence check script (`9ae32a3`) is the lightweight substitute until then

---

## Delivery Order

```
Phase 1a — docs/bridge.md                    (new doc, highest ROI)
Phase 1b — README.md "Start Here" prepend    (additive edit, fast)
Phase 1c — docs/learning-path.md             (new doc, fast)
Phase 2a — langchain_tool_lab                (new camazotz lab)
Phase 2b — function_call_injection_lab       (new camazotz lab)
Phase 2c — Walkthrough 8                     (new agentic-sec doc)
Phase 3   — contribution template, GH Action, taxonomy YAML (future)
```

Commit shape:
- **agentic-sec commit 1:** `docs/bridge.md` + `docs/learning-path.md` + README "Start Here" prepend
- **camazotz commit:** `langchain_tool_lab` + `function_call_injection_lab` (both labs + tests in one commit)
- **agentic-sec commit 2:** Walkthrough 8
- **CHANGELOG update:** After all above land, a single 2026-05 entry covering this sprint + the test/coverage work from earlier today

---

## What Does NOT Change

- All existing README content below "Start Here" — untouched
- `identity-flows.md` — untouched
- `ecosystem.md` — untouched
- `golden-path.md` — untouched
- All 7 existing walkthroughs — untouched
- All reference docs (`camazotz.md`, `nullfield.md`, `mcpnuke.md`) — untouched
- The 35 existing labs — untouched
- nullfield, mcpnuke repos — no changes for Phase 1-2

---

## Success Criteria

A security practitioner who knows OWASP API Top 10 and JWT attacks but has never seen an MCP server can:
1. Read `bridge.md` and explain what makes MCP tool invocation different from REST API calls
2. Name the five transport surfaces and give a real-world framework example for each
3. Explain why identity lane matters and give a concrete attack example for Lane 4
4. Follow the Red Team or Blue Team learning track to completion without getting lost
5. Look at a `langchain_tool_lab` or `function_call_injection_lab` result and connect it to their existing knowledge of injection attacks
