# Why This Stack — an argumentative primer

A conversational companion to [`STACK.md`](STACK.md). Follows one agentic request
from start to finish and explains what each layer *solves*, not just what it *is*.

---

## The one problem this solves

Your agent decides what tools to call. Your agent can be injected, confused, or
social-engineered. Therefore your agent is not the thing that should enforce
security. Full stop.

Everything below follows from that single premise. If you trust the LLM to be
the gate, you don't need any of this. If you don't — and you shouldn't — then
the question becomes: *where do you put the real gates, and what does each one
contribute that the others can't?*

---

## Dissecting one request, end to end

An agent wants to call `cred_broker.read_credential` with an argument
`api_key: sk-LEAKME…`. Let's follow it through the stack and see what happens
at each hop — and *why* that hop exists.

### Hop 0: the agent sends the request

```json
POST /mcp
x-principal: ci-deployer
{"jsonrpc":"2.0","method":"tools/call","params":{"name":"cred_broker.read_credential","arguments":{"api_key":"sk-LEAKME..."}}}
```

At this point nothing has checked anything. The request is on the wire.

---

### Hop 1: the Istio waypoint (Envoy)

**What it is:** a shared Envoy proxy that all traffic to the workload must pass
through. It's not a sidecar; it's a namespace-level checkpoint provided by Istio
ambient.

**What it does to this request:**
1. Verifies the caller has a valid mesh identity (mTLS / SPIFFE SVID via ztunnel).
   A non-mesh caller is refused here — you can't even reach the workload without a
   crypto identity.
2. Buffers the JSON-RPC body and sends it to OPA (the PDP) via `ext_authz`:
   *"principal=ci-deployer, method=tools/call, tool=cred_broker.read_credential —
   allow or deny?"*
3. OPA evaluates `authz.rego`: ci-deployer has an explicit grant for
   `cred_broker.read_credential` → ALLOW.
4. If the principal were `unknown` or the tool were `delete_everything`: no grant
   → default deny → **HTTP 403**, workload never touched.

**Why this exists (what it solves that nothing else does):**
- **Coarse identity-based authorization.** "May THIS principal call THIS tool at
  all?" — answered deterministically, not by the LLM.
- **Non-bypassability.** Because the waypoint is in the *network path* (not a
  library the app opts into), the agent can't route around it. Pair with
  `waypoint-for: all` and even pod-IP-direct calls are gated.
- **One policy brain.** OPA serves both this waypoint and nullfield — one Rego
  corpus governs everything.

**What it does NOT do:** it can't inspect the *content* of the tool arguments,
can't redact secrets from the response, can't hold for human approval, can't
enforce per-identity budgets. It's allow/deny per principal+tool, period.

---

### Hop 2: nullfield (the MCP-aware PEP)

**What it is:** a Go sidecar sitting in front of the workload (`:9090` →
`:8080`). It parses the MCP JSON-RPC call and applies five actions.

**What it does to this request:**
1. Parses the tool name (`cred_broker.read_credential`) and looks up the policy.
2. The policy says: **SCOPE** — allow, but *modify in transit*.
3. SCOPE strips the `api_key` argument from the request body before forwarding.
4. After the tool responds, SCOPE applies regex redaction patterns to the response
   body (any AWS keys, JWTs, DB URLs → `[REDACTED-BY-NULLFIELD]`).
5. The agent gets a useful (sanitized) response. The secret never leaves the
   security boundary.

**Why this exists (what it solves that the waypoint can't):**
- **HOLD** — park the request and wait for a human to approve it via an admin API.
  The waypoint is allow/deny; it can't *pause* a request.
- **SCOPE** — modify the request/response in transit. Strip secret arguments,
  redact secret values, inject credentials. The waypoint forwards or blocks; it
  can't rewrite.
- **BUDGET** — per-identity call quotas (maxCallsPerHour). The waypoint has no
  concept of "this principal has used 4 of their 5 allowed calls today."
- **MCP awareness** — nullfield understands that `tools/call` has a `params.name`
  field, that the response has a `result.content` array, that JSON-RPC error codes
  have semantics (-32000 = policy deny, -32005 = hold timeout). The waypoint sees
  opaque HTTP.

**What it does NOT do:** it doesn't handle identity verification (trusts the mesh
for that), doesn't handle network reachability, doesn't gate model egress.

---

### Hop 3: the workload executes the tool

The request reaches `brain-gateway:8080` with the secret *already stripped*. The
tool runs. If it needs an LLM, it calls outbound to the model provider.

---

### Hop 4: the Envoy AI Gateway (egress)

**What it is:** a separate Envoy (not the waypoint — a different one) that sits
on the *outbound* model-call path. Where the waypoint gates inbound tool calls,
this gates outbound LLM calls.

**What it does:**
1. The workload calls `POST /v1/chat/completions` with `model: qwen3:4b`.
2. The AI Gateway checks its `AIGatewayRoute`: is `qwen3:4b` in the allowlist?
   Yes → proxy to the backend (Ollama). Count input/output tokens in the access
   log (cost accounting).
3. If the model were `llama3.2:1b` (which Ollama has pulled, but policy doesn't
   allow): **404 No matching route.** The workload can't reach that model even
   though the backend has it.

**Why this exists (what it solves that nothing else does):**

This is the piece people confuse with the waypoint, so let me be explicit about
what's different:

| | Waypoint (Envoy + OPA) | AI Gateway (Envoy) |
|--|--|--|
| **Direction** | Inbound (client → MCP server) | Outbound (MCP server → LLM provider) |
| **Protocol** | MCP JSON-RPC (`tools/call`) | OpenAI API (`/v1/chat/completions`) |
| **Decision** | "May this principal call this tool?" | "May this workload use this model?" |
| **Identity** | Checks the *caller's* identity | Injects the *provider's* credential |
| **Data** | Doesn't touch request body (allow/deny only) | Counts tokens, logs cost |

The AI Gateway solves three things the waypoint structurally can't:

1. **Model allowlist.** "Which models can agents use?" is a policy question. The
   backend might host 30 models; policy says you can reach 2. Without this, a
   compromised workload calls any model it wants — including expensive frontier
   models (cost runaway) or unapproved models (compliance).

2. **Credential brokering.** The provider API key (OpenAI, Bedrock, etc.) lives in
   ONE place — the `BackendSecurityPolicy`. The workload never holds it. So a
   compromised agent can't exfiltrate the key. Rotation is one spot.

3. **Token-cost accounting.** Every request logs input/output tokens in the Envoy
   access log. This is the hook for per-agent cost caps and billing attribution —
   the defense against an injected agent looping expensive calls.

**What it does NOT do:** it doesn't understand MCP tool calls, doesn't check who
the *user* is, doesn't enforce per-tool policy. It's purely about what *leaves*
to model providers.

---

### Why you can't skip any piece

| If you remove... | What breaks |
|---|---|
| The waypoint + OPA | Any principal calls any tool. An injected agent runs `delete_everything` unchecked. |
| nullfield | No hold-for-approval, no secret stripping, no budgets. A credential-read leaks the raw secret. A prompt-rewrite persists silently. |
| The AI Gateway | Any workload calls any model, burns unlimited budget, or exfiltrates the provider key. |
| Gatekeeper | A poisoned pod with `privileged: true` + host mount deploys silently. |
| NetworkPolicy / mesh mTLS | A pod that bypasses the waypoint reaches the workload directly. |

Each layer answers ONE question. Remove it and that question goes unanswered.

---

## "But isn't this overkill?"

The natural objection. The answer depends on what you're protecting:

- If your agent is a local coding assistant with no secrets access: yes, overkill.
  Use skillseraph (static scan) and move on.
- If your agent runs in production, calls tools that touch real data, and any user
  on the internet can influence its inputs (RAG, email, web content): this is the
  *minimum* credible defense. Every component here corresponds to a real attack
  class we've demonstrated working.

The design principle is **defense in depth for agentic systems** — the same way
you layer network segmentation, IAM, WAF, and encryption for traditional services.
The difference is that traditional services don't have an LLM *inside* them making
security-relevant decisions based on attacker-influenced context.

---

## The feedback loop (offense proves defense)

The stack isn't self-certifying. We validate it with offense:

1. **mcpnuke** scans the target *without* the control plane → finds executable
   attack chains (prompt injection → code execution → token theft).
2. Same scan *through* the control plane → 285 tool.denied, 4 tool.allowed at
   runtime. The chains are inert.
3. **skillseraph** scans the agent *configs* at rest → finds poisoned rules,
   planted skills, encoded payloads → generates a nullfield policy that blocks
   the corresponding tools.

This is the "scan → gate → prove" loop. It's not enough to deploy controls; you
have to prove the controls actually stop the attacks the scanner finds.

---

## Summary: one sentence per layer

| Layer | One sentence |
|-------|--------------|
| **Istio ambient + waypoint** | Every workload gets a crypto identity and a shared L7 checkpoint — no app changes, no sidecars, non-bypassable. |
| **OPA** | One policy brain (deny-by-default Rego) that both enforcement points call — swap the PEP, keep the policy. |
| **nullfield** | The MCP-aware gate: hold for humans, strip secrets, cap budgets — the three things a generic proxy can't do because it doesn't understand the tool call. |
| **AI Gateway** | The only way model traffic leaves: policy-controlled model catalog, token accounting, credential isolation. |
| **Gatekeeper** | Deploy-time hygiene: no rogue pods, no wrong registries, no missing labels. |
| **NetworkPolicy** | L3/L4 fence: only intended pods reach the workload (or rely on mesh mTLS as the CNI-independent equivalent). |

---

*Companion to [`STACK.md`](STACK.md) (the reference) and [`STATUS.md`](STATUS.md)
(what's proven). Run `verify-stack.sh` to watch all of this in action; run
`observability/walk-stack.sh` to see the raw requests at each hop.*
