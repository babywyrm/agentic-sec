# Walkthrough 3: Lab Practice

Write nullfield policy by hand. The defense-mode labs score your policy
on effectiveness and precision.

**Time:** 20 minutes
**Prerequisites:** camazotz running locally

---

## Lab A: Policy Authoring

**Goal:** Write a nullfield policy that blocks a known 3-step attack chain.

### Get the attack chain

```bash
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{
    "name":"policy_authoring.get_attack_chain","arguments":{}}}' | python3 -m json.tool
```

You'll see three tools forming an attack chain:
1. `hallucination.execute_plan` — code execution (CRITICAL)
2. `shadow.register_webhook` — webhook persistence (HIGH)
3. `relay.execute_with_context` — token theft (HIGH)

### Write and submit your policy

```bash
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{
    "name":"policy_authoring.submit_policy","arguments":{
      "policy_yaml":"rules:\n  - action: HOLD\n    toolNames: [hallucination.execute_plan]\n    hold: {timeout: 5m, onTimeout: DENY}\n  - action: DENY\n    toolNames: [shadow.register_webhook]\n  - action: SCOPE\n    toolNames: [relay.execute_with_context]\n    scope: {response: {redactPatterns: [password, secret, token]}}\n  - action: DENY\n    toolNames: [\"*\"]"
    }}}' | python3 -m json.tool
```

Score >= 80 = flag captured. The LLM evaluates your policy against the
attack chain and gives feedback on what's missing.

---

## Lab B: Response Inspection

**Goal:** Write SCOPE redactPatterns that catch credential leaks without
breaking legitimate output.

### See what leaks

```bash
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{
    "name":"response_inspection.call_leaky_tool","arguments":{}}}' | python3 -m json.tool
```

On easy difficulty: plain text `password` field. On medium: Bearer token
in headers. On hard: base64-encoded secrets.

### Submit your patterns

```bash
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{
    "name":"response_inspection.submit_redaction","arguments":{
      "patterns":["password","secret","Bearer\\\\s+\\\\S+","sk-[a-zA-Z0-9]+"]
    }}}' | python3 -m json.tool
```

The lab shows your coverage percentage and gives you a `scope_config` block
you can copy directly into a nullfield policy.

---

## Lab C: Budget Tuning

**Goal:** Set rate limits that block cost exhaustion without affecting
legitimate users.

### See the traffic pattern

```bash
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{
    "name":"budget_tuning.get_traffic_pattern","arguments":{}}}' | python3 -m json.tool
```

Legitimate users: 5-12 calls/hour. Attackers: 150-200 calls/hour.

### Simulate your budget

```bash
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{
    "name":"budget_tuning.simulate","arguments":{
      "budget_config":{
        "perIdentity":{"maxCallsPerHour":30},
        "perSession":{"maxCallsPerHour":15},
        "onExhausted":"DENY"
      }}}}' | python3 -m json.tool
```

Shows which users and attackers get blocked with your limits.

### Submit for scoring

```bash
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{
    "name":"budget_tuning.submit_budget","arguments":{
      "budget_config":{
        "perIdentity":{"maxCallsPerHour":30},
        "perSession":{"maxCallsPerHour":15},
        "onExhausted":"DENY"
      }}}}' | python3 -m json.tool
```

Combined score (security + usability) >= 80 = flag captured.

---

## What You've Learned

After these three walkthroughs:

1. **You can scan** any MCP server for vulnerabilities with mcpnuke
2. **You can generate** nullfield policy from scan findings automatically
3. **You can write** DENY, HOLD, SCOPE, and BUDGET rules by hand
4. **You can validate** that your defenses actually block the attacks
5. **You can tune** rate limits for mixed traffic patterns

This is the complete defensive skill set for MCP tool security.
