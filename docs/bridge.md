# MCP Security for the Security Practitioner

You know security. You know OWASP API Top 10, JWT attacks, SSRF, injection,
confused deputy. Most of that knowledge transfers here — but MCP and agentic
AI patterns are 1-2 year old RFCs, and some of your existing intuitions fail
in specific, non-obvious ways.

This document does the translation work once. Read it before the walkthroughs
and the labs will click faster.

---

## The Protocol in Two Paragraphs

[Model Context Protocol (MCP)](https://spec.modelcontextprotocol.io/) defines
one thing: how an LLM client discovers and calls tools. It specifies tool
registration (`tools/list`), tool invocation (`tools/call`), and a JSON-RPC
2.0 message envelope. That is the entire spec.

What MCP deliberately does **not** specify: authentication, authorization,
transport security, identity propagation, rate limiting, audit logging. Those
are left to implementations. Today, most MCP servers implement none of them.
The attack surface is those gaps — not the protocol itself.

---

## Your Mental Model, Audited

| What you already know | Transfers? | What's different in MCP/agentic |
|---|---|---|
| **REST authentication** (API keys, OAuth2, JWT bearer) | Partially | Token-based auth still applies, but the *caller* may be an AI model acting on a human's behalf. The model can be manipulated into using the token for calls the user never intended — the "confused deputy" problem. The human issued a token; the model decided how to spend it. |
| **Input validation** | Yes — and extends further | Still validate tool arguments. But in MCP the entity *generating* the input is often the LLM itself. The model can be the attack vector: prompt injection causes the model to construct malicious tool arguments. Tool *descriptions* are also input surfaces — the model reads them. |
| **SSRF** | Yes — and dramatically worse | Any tool that fetches a URL is an SSRF vector. In MCP, prompt injection can redirect *any* LLM conversation with a fetch tool toward internal targets. The model doesn't distinguish legitimate from injected URL instructions; it's eager to help. The SSRF surface is as large as the model's context window. |
| **JWT audience checks** | Yes — but multi-agent chains break them | `aud` claim enforcement still applies. The new failure mode: in a delegation chain (human → agent A → agent B → MCP server), the token issued to agent A is reused by agent B, which calls a service that expects `aud=service-b`. The original audience claim no longer reflects reality. |
| **Output sanitization** | Partially new | You sanitize *input* to prevent injection. In MCP, tool *output* also requires sanitization — tool responses go back into the LLM's context window. Malicious content in a tool response can poison subsequent model decisions (indirect prompt injection, cross-tool context poisoning). There is no REST analogue. |
| **Rate limiting** | Yes — with a twist | Standard rate limiting applies. The new vector: a single LLM call can fan out into dozens of tool calls in one agent loop. Per-identity and per-session rate limiting matters more than per-IP. |
| **Audit logging** | Yes — harder to attribute | Tool calls need audit trails. Attribution is harder: was this call made by the human, the agent, or an injected instruction? Identity lane (see below) determines what "attribution" means for each call class. |
| **OWASP API Top 10** | Maps to OWASP MCP Top 10 | See table below. |

### OWASP MCP Top 10 — Quick Map

| OWASP MCP | Name | REST/API analogue |
|---|---|---|
| MCP01 | Prompt Injection | Injection (A03) — but the injected content targets the model's reasoning, not a parser |
| MCP02 | Insecure Tool Output Handling | XSS (A03) — but the "browser" is the LLM's context window |
| MCP03 | Tool / Resource Poisoning | Supply Chain (A08) — tool descriptions and resource URIs as attack surfaces |
| MCP04 | Excessive Permissions | Broken Access Control (A01) — tools granted more capability than needed |
| MCP05 | Missing Authentication | Security Misconfiguration (A05) — no auth on the MCP endpoint is the default |
| MCP06 | Sensitive Data Exposure | Sensitive Data Exposure (A02) — but the exfiltration channel is the model's output |
| MCP07 | Insecure Tool Execution | Broken Function Level Auth (API08) — tool invocation without enforcement |
| MCP08 | Unsafe Agentic Loops | BOLA (API01) — but at the agent loop level, not the resource level |
| MCP09 | Inadequate Audit | Logging Failures (A09) — call attribution is the new challenge |
| MCP10 | LLM Supply Chain | Software/Data Integrity (A08) — prompt templates and fine-tuned models as supply chain |

---

## The Five Transport Surfaces

MCP JSON-RPC is one way an LLM calls a tool. In practice you will encounter
five distinct transport surfaces, each with different security properties. The
labs in camazotz cover all five; so do the checks in mcpnuke.

| Code | Transport | Real-world runtimes | Identity envelope |
|---|---|---|---|
| **A** | MCP JSON-RPC | Claude Desktop, any MCP client, Cursor, VS Code MCP extensions | `Mcp-Session-Id` header; optional Bearer token; no built-in auth |
| **B** | Direct HTTP API | Raw REST calls to a tool server, bypassing the MCP layer entirely | Standard HTTP auth (Bearer, mTLS, API key) — but bypasses MCP-level controls |
| **C** | In-process SDK | LangChain `@tool`, Anthropic Python SDK `tool_use` helper, OpenAI `tools=` param | Python function call; identity is whatever the caller passes; no wire protocol |
| **D** | Subprocess / CLI | Shell-calling agents, `bash` tool use, agent-driven CLI pipelines | OS-level process identity; stdin/stdout; no auth layer by default |
| **E** | Native function-calling | OpenAI `function_call`, Claude `tool_use` JSON outside MCP, Gemini function-calling | Model provider API key + function schema; no end-user identity in the envelope |

**The practitioner implication:** if you are reviewing a deployment that uses
LangChain, you are looking at Transport C. If the agent also shells out, that
is Transport D. mcpnuke checks Transport A by default; the other surfaces
require different probing strategies (static analysis, SDK instrumentation).
The camazotz labs let you explore each surface hands-on.

---

## The Identity Problem

REST APIs have one caller model: a client authenticates and calls an endpoint.
MCP and agentic deployments have five, and they have radically different
security properties. These are the **identity lanes**:

| Lane | Who is calling the tool? | Security implication |
|---|---|---|
| **1 — Human Direct** | A human, through an MCP client | Closest to REST. The human's token is in play; the risk is the model misusing it. |
| **2 — Delegated** | A human authorized an agent; the agent is now the caller | The human's intent may not match the agent's action. Scope narrowing is required. |
| **3 — Machine** | No human in the loop; a service calls another service | Certificate-based machine identity (e.g., Teleport tbot). No human to alert. Blast radius of a compromise is higher. |
| **4 — Agent → Agent** | Agent A delegated to Agent B which called Agent C | Who authorized the last hop? Delegation depth erodes the original authorization. At depth 3+ there is often no traceable human authorization remaining. |
| **5 — Anonymous** | No identity claim at all | The default for most MCP deployments today. Every call is unauthenticated. This is the most common, most dangerous starting point. |

A security practitioner reviewing a REST API asks "is the caller authenticated
and authorized?" In MCP, the prior question is "which lane is this call in?"
The answer changes what controls are appropriate.

---

## Where to Go Next

```
You're here → bridge.md (you're reading it)

Want to attack a live MCP server?
  → docs/walkthroughs/attack.md  (Walkthrough 1 — 30 min)

Want to write nullfield policy to defend one?
  → docs/walkthroughs/defense.md  (Walkthrough 2 — 45 min)

Want to run the full scan → enforce → validate loop?
  → docs/walkthroughs/live-loop.md  (Walkthrough 5 — 20 min)

Want a structured curriculum (red team / blue team / full loop)?
  → docs/learning-path.md

Want the deep architecture for a production deployment?
  → docs/golden-path.md

Want the formal 5×5 lane × transport reference?
  → docs/identity-flows.md
```

---

*This document bridges from general security knowledge into the MCP/agentic
threat model. It does not replace the full reference docs — it points to them.*
