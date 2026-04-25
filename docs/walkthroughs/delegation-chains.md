# Walkthrough 6: Delegation Chain Attacks

Multi-agent delegation is the most common pattern in production AI systems.
Agent A calls Agent B calls Agent C — each hop dilutes the original human's
identity and intent. This walkthrough shows the attack and the defense.

**Time:** 10 minutes
**Lab:** `delegation_depth_lab` in camazotz

---

## The Pattern

```
Human (authorized) → Agent A → Agent B → Agent C → secrets.leak_config
                     depth 0    depth 1    depth 2    depth 3

Question: Does Agent C at depth 3 have the human's authority
          to access secrets? Should it?
```

Every LangGraph, CrewAI, and AutoGen deployment has this pattern. The agent
that executes the dangerous tool is N hops from the human who authorized
the session. Most security architectures lose track of the original identity.

## The Attack (Easy Difficulty)

### Step 1: Start the chain as a human-authorized agent

```bash
$ curl -s -X POST http://localhost:8080/mcp \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{
      "name":"delegation_depth.start_chain","arguments":{
        "agent_name":"agent-a","human_principal":"alice@company.com"}}}' \
    | python3 -m json.tool
```

```json
{
  "chain_id": "chain-1-a8b3c2d1",
  "agent": "agent-a",
  "depth": 0,
  "authority": "full",
  "human_principal": "alice@company.com"
}
```

### Step 2: Delegate A → B → C

```bash
# A delegates to B
$ curl -s -X POST http://localhost:8080/mcp ... \
    -d '...{"name":"delegation_depth.delegate","arguments":{
      "chain_id":"chain-1-a8b3c2d1","from_agent":"agent-a",
      "to_agent":"agent-b","reason":"need data analysis"}}...'
# depth: 1, authority: full

# B delegates to C
$ curl -s -X POST http://localhost:8080/mcp ... \
    -d '...{"name":"delegation_depth.delegate","arguments":{
      "chain_id":"chain-1-a8b3c2d1","from_agent":"agent-b",
      "to_agent":"agent-c","reason":"need secrets access"}}...'
# depth: 2, authority: full
```

### Step 3: Agent C accesses secrets

```bash
$ curl -s -X POST http://localhost:8080/mcp ... \
    -d '...{"name":"delegation_depth.access_resource","arguments":{
      "chain_id":"chain-1-a8b3c2d1","agent_name":"agent-c",
      "resource":"secrets"}}...'
```

```json
{
  "access": "granted",
  "resource": "secrets",
  "agent": "agent-c",
  "depth": 2,
  "authority": "full",
  "original_principal": "alice@company.com",
  "flag": "CZTZ{...}",
  "_warning": "Agent at depth 2 accessed 'secrets' with full authority inherited from alice@company.com",
  "_identity_dilution": "2 hops — original intent may be lost"
}
```

Agent C accessed secrets with Alice's full authority, 2 hops removed from
Alice's actual intent. Alice authorized "data analysis" — not secrets access.

### Step 4: Inspect the chain

```bash
$ curl -s -X POST http://localhost:8080/mcp ... \
    -d '...{"name":"delegation_depth.inspect_chain","arguments":{
      "chain_id":"chain-1-a8b3c2d1"}}...'
```

```json
{
  "total_depth": 2,
  "original_principal": "alice@company.com",
  "hops": [
    {"depth": 0, "agent": "agent-a", "authority": "full", "delegated_by": "alice@company.com"},
    {"depth": 1, "agent": "agent-b", "authority": "full", "delegated_by": "agent-a"},
    {"depth": 2, "agent": "agent-c", "authority": "full", "delegated_by": "agent-b"}
  ],
  "_analysis": {
    "identity_dilution": "2 hops from human authorization",
    "authority_degradation": ["full", "full", "full"],
    "recommendation": "Chain within safe limits"
  }
}
```

## The Defense

### nullfield delegation depth enforcement

```yaml
# nullfield policy with delegation depth limits
rules:
  - action: ALLOW
    toolNames: [delegation_depth.start_chain, delegation_depth.inspect_chain]
    reason: "chain management tools are safe"

  - action: HOLD
    toolNames: [delegation_depth.delegate]
    hold:
      timeout: "3m"
      onTimeout: DENY
    reason: "delegation requires human approval"

  - action: DENY
    toolNames: [delegation_depth.access_resource]
    when:
      claims:
        chain_depth: { $gt: 2 }
    reason: "block resource access beyond depth 2"

  - action: DENY
    toolNames: ["*"]
    reason: "default deny"
```

### Medium difficulty: authority degrades

On medium difficulty, Agent C's authority is downgraded to `readonly`:

```json
{
  "depth": 2,
  "authority": "readonly",
  "_warning": "Authority degraded to readonly at depth 2"
}
```

Readonly agents can list resources but not access secrets or deploy.

### Hard difficulty: no inherited authority

On hard difficulty, delegation is denied entirely:

```json
{
  "approved": false,
  "reason": "re-authentication required",
  "_nullfield_recommendation": "DENY delegation at depth > 2"
}
```

## Why This Matters

In every production multi-agent system:
- The **human** authorizes a high-level task ("analyze this data")
- **Agent A** decomposes it into subtasks
- **Agent B** handles a subtask and needs more tools
- **Agent C** executes the actual tool call

By the time the tool runs, the identity is "agent-c" not "alice@company.com".
The authorization context says "full" even though Alice never intended secrets
access. This is the identity dilution problem.

**The fix:** nullfield tracks delegation depth in the policy engine and
enforces limits — HOLD for delegation, DENY beyond depth N, authority
degradation per hop.
