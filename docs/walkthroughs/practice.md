# Walkthrough 3: Lab Practice

Write nullfield policy by hand. The defense-mode labs score your policy
on effectiveness and precision.

**Time:** 20 minutes
**Tested on:** Docker Compose (localhost:8080)

---

## Lab A: Policy Authoring

**Goal:** Write a nullfield policy that blocks a known 3-step attack chain.

### Step 1: Get the attack chain

```bash
$ curl -s -X POST http://localhost:8080/mcp \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call",
         "params":{"name":"policy_authoring.get_attack_chain","arguments":{}}}' \
    | python3 -m json.tool
```

Output (formatted):

```json
{
  "chain_id": "AC-001",
  "description": "Prompt injection -> code execution -> secret exfiltration",
  "steps": [
    {"tool": "hallucination.execute_plan", "finding": "code_execution", "severity": "CRITICAL"},
    {"tool": "shadow.register_webhook", "finding": "webhook_persistence", "severity": "HIGH"},
    {"tool": "relay.execute_with_context", "finding": "token_theft", "severity": "HIGH"}
  ],
  "recommended_actions": {
    "hallucination.execute_plan": "HOLD",
    "shadow.register_webhook": "DENY",
    "relay.execute_with_context": "SCOPE"
  }
}
```

### Step 2: Write and submit your policy

```bash
$ curl -s -X POST http://localhost:8080/mcp \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/call",
         "params":{"name":"policy_authoring.submit_policy","arguments":{
           "policy_yaml":"rules:\n  - action: HOLD\n    toolNames: [hallucination.execute_plan]\n    hold: {timeout: 5m, onTimeout: DENY}\n  - action: DENY\n    toolNames: [shadow.register_webhook]\n  - action: SCOPE\n    toolNames: [relay.execute_with_context]\n    scope: {response: {redactPatterns: [password, secret, token]}}\n  - action: DENY\n    toolNames: [\"*\"]"
         }}}'
```

The LLM evaluates your policy and responds with a score and feedback:

```json
{
  "evaluation": {
    "valid": true,
    "score": 95,
    "feedback": "Excellent policy. HOLD for execute_plan, DENY for register_webhook, SCOPE with redaction for execute_with_context. Default DENY catches everything else."
  },
  "_defense_status": "ATTACK CHAIN BLOCKED"
}
```

Score >= 80 = flag captured.

---

## Lab B: Response Inspection

**Goal:** Write SCOPE redactPatterns that catch credential leaks without
breaking legitimate output.

### Step 1: See what leaks

```bash
$ curl -s -X POST http://localhost:8080/mcp \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call",
         "params":{"name":"response_inspection.call_leaky_tool","arguments":{}}}' \
    | python3 -m json.tool
```

Output (easy difficulty):

```json
{
  "tool_response": {
    "status": "ok",
    "data": {
      "username": "admin",
      "password": "Sup3rS3cret!2026",
      "database": "production-db",
      "connection_string": "postgres://admin:Sup3rS3cret!2026@db.internal:5432/prod"
    }
  }
}
```

The `password` and `connection_string` fields contain credentials that
should never reach the LLM.

### Step 2: Submit redaction patterns

```bash
$ curl -s -X POST http://localhost:8080/mcp \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/call",
         "params":{"name":"response_inspection.submit_redaction","arguments":{
           "patterns":["Sup3rS3cret!2026","password","connection_string","postgres://[^\\\\s]+"]
         }}}'
```

Output:

```json
{
  "coverage_pct": 100,
  "sensitive_caught": 2,
  "sensitive_total": 2,
  "_defense_status": "REDACTION EFFECTIVE",
  "scope_config": {
    "response": {
      "redactPatterns": ["Sup3rS3cret!2026", "password", "connection_string", "postgres://[^\\s]+"],
      "redactReplacement": "[REDACTED]"
    }
  }
}
```

100% coverage. The `scope_config` block is ready to paste directly into a
nullfield policy YAML.

---

## Lab C: Budget Tuning

**Goal:** Set rate limits that block cost exhaustion without affecting
legitimate users.

### Step 1: See the traffic pattern

```bash
$ curl -s -X POST http://localhost:8080/mcp \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call",
         "params":{"name":"budget_tuning.get_traffic_pattern","arguments":{}}}' \
    | python3 -m json.tool
```

Output:

```json
{
  "legitimate_users": [
    {"identity": "user-alice", "calls_per_hour": 8, "pattern": "steady"},
    {"identity": "user-bob", "calls_per_hour": 5, "pattern": "steady"},
    {"identity": "user-carol", "calls_per_hour": 12, "pattern": "bursty"}
  ],
  "attackers": [
    {"identity": "attacker-1", "calls_per_hour": 150, "pattern": "sustained"},
    {"identity": "attacker-2", "calls_per_hour": 200, "pattern": "burst", "burst_size": 50}
  ],
  "cost_per_call": 0.02
}
```

Legitimate users: 5-12 calls/hour. Attackers: 150-200 calls/hour. The gap
is wide — a limit around 30 calls/hour blocks all attackers while allowing
all legitimate traffic.

### Step 2: Simulate your budget

```bash
$ curl -s -X POST http://localhost:8080/mcp \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/call",
         "params":{"name":"budget_tuning.simulate","arguments":{
           "budget_config":{"perIdentity":{"maxCallsPerHour":30},"perSession":{"maxCallsPerHour":15},"onExhausted":"DENY"}
         }}}' | python3 -m json.tool
```

Output:

```json
{
  "simulation_results": [
    {"identity": "user-alice", "calls": 8, "blocked": false, "type": "legitimate"},
    {"identity": "user-bob", "calls": 5, "blocked": false, "type": "legitimate"},
    {"identity": "user-carol", "calls": 12, "blocked": false, "type": "legitimate"},
    {"identity": "attacker-1", "calls": 150, "blocked": true, "type": "attacker"},
    {"identity": "attacker-2", "calls": 200, "blocked": true, "type": "attacker"}
  ],
  "legitimate_blocked": 0,
  "attackers_blocked": 2,
  "false_positive_rate": 0.0
}
```

Zero false positives, both attackers blocked.

### Step 3: Submit for scoring

```bash
$ curl -s -X POST http://localhost:8080/mcp \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":3,"method":"tools/call",
         "params":{"name":"budget_tuning.submit_budget","arguments":{
           "budget_config":{"perIdentity":{"maxCallsPerHour":30},"perSession":{"maxCallsPerHour":15},"onExhausted":"DENY"}
         }}}'
```

Combined score (security + usability) >= 80 = flag captured.

---

## What You've Learned

| Skill | How You Practiced |
|-------|------------------|
| Scan MCP servers | Walkthrough 1: mcpnuke --fast --no-invoke |
| Generate policy | Walkthrough 2: mcpnuke --generate-policy |
| Apply policy | Walkthrough 2: kubectl apply (CRD) or ConfigMap |
| Write DENY/HOLD rules | Lab A: block an attack chain |
| Write SCOPE rules | Lab B: redact credentials in responses |
| Write BUDGET rules | Lab C: rate-limit attackers without blocking users |
| Validate defenses | Walkthrough 2: re-scan with --baseline |

This is the complete defensive skill set for MCP tool security. Every command
shown here was tested against both Docker Compose and a K3s cluster deployment.
