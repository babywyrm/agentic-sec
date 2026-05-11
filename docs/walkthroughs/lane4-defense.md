# Walkthrough 11: Building a Lane 4 Defense from Scratch

How to reason about multi-agent identity dilution, write a nullfield policy
that enforces it, and validate the controls hold under each of the five
Lane 4 transport patterns.

**Time:** 20 minutes
**Labs:** `delegation_depth_lab`, `delegation_chain_lab`, `agent_chain_direct_api_lab` (MCP-T45), `agent_sdk_chain_lab` (MCP-T47), `agent_subprocess_chain_lab` (MCP-T48), `agent_llm_chain_lab` (MCP-T49)

---

## The Lane 4 Problem

Lane 4 is any flow where one agent calls another. The security question is
always the same:

```
Agent A calls Agent B.

Does Agent B know:
  - Who originally authorized this chain? (the human principal)
  - What scope Agent A had at the time of delegation?
  - Whether Agent A was allowed to delegate this particular task?

Does the audit log record:
  - Agent A's identity?
  - Agent B's identity?
  - The delegation event between them?
```

In most production deployments, the answer to all of these is "no." The
five transport patterns each introduce the same gap through a different
mechanism:

| Transport | How Agent B is invoked | How credential crosses boundary | Identity in audit log |
|-----------|------------------------|----------------------------------|----------------------|
| A — MCP | Separate MCP server call | Bearer token forwarded in request | Depends on gateway config |
| B — Direct API | HTTP REST call | Bearer token in Authorization header | Usually just Agent A |
| C — In-process SDK | Library function call | Shared process memory | Never Agent B |
| D — Subprocess | `subprocess.Popen` | Environment variable injection | PID only, no identity |
| E — LLM function-calling | LLM dispatches function | Full conversation context passed | LLM provider logs only |

The defense primitives are the same regardless of transport. The nullfield
policy just needs to match on the right tool names.

---

## Step 1 — Observe the Gap (Easy Difficulty)

Start with the simplest chain — MCP Transport A.

```bash
make up

curl -sf http://localhost:8080/config \
  -H 'Content-Type: application/json' \
  -d '{"difficulty": "easy"}'

# Start a delegation chain as a human principal
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 1, "method": "tools/call",
    "params": {
      "name": "delegation_depth.start_chain",
      "arguments": {
        "agent_name": "agent-a",
        "human_principal": "alice@company.com"
      }
    }
  }' | python3 -c "
import sys, json
r = json.load(sys.stdin)
d = json.loads(r['result']['content'][0]['text'])
print('chain_id:', d.get('chain_id'))
print('depth:', d.get('depth'))       # 0 — human authorized
print('authority:', d.get('authority'))
"

# Delegate A → B → C — each hop, check what authority looks like
for from_agent, to_agent in [('agent-a', 'agent-b'), ('agent-b', 'agent-c')]:
    curl -sf http://localhost:8080/mcp \
      -H 'Content-Type: application/json' \
      -d "{
        \"jsonrpc\": \"2.0\", \"id\": 2, \"method\": \"tools/call\",
        \"params\": {
          \"name\": \"delegation_depth.delegate\",
          \"arguments\": {
            \"chain_id\": \"<chain_id_from_above>\",
            \"from_agent\": \"$from_agent\",
            \"to_agent\": \"$to_agent\",
            \"reason\": \"need downstream processing\"
          }
        }
      }" | python3 -c "
import sys, json
r = json.load(sys.stdin)
d = json.loads(r['result']['content'][0]['text'])
print('depth:', d.get('depth'), '| authority:', d.get('authority'), '| limit_enforced:', d.get('_depth_limit_enforced'))
"
```

**What you see on easy:** `authority: full` at every depth. Agent C at depth 2
has the same authority as the human principal at depth 0. The depth limit is
not enforced.

---

## Step 2 — Observe In-Process Identity Erasure (Transport C)

Switch to the SDK chain pattern where identity erasure is total:

```bash
# Load sub-agent in-process
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 3, "method": "tools/call",
    "params": {
      "name": "chain.load_agent",
      "arguments": {
        "agent_id": "deploy-subagent",
        "capability": "admin",
        "caller_token": "alice-bearer-cztz"
      }
    }
  }'

# Read audit log — sub-agent is invisible
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 4, "method": "tools/call",
    "params": {
      "name": "chain.read_audit_log",
      "arguments": {}
    }
  }' | python3 -c "
import sys, json
r = json.load(sys.stdin)
d = json.loads(r['result']['content'][0]['text'])
entries = d.get('entries', [])
print('audit entries:', len(entries))
actors = [e.get('actor') for e in entries]
print('actors:', actors)
# deploy-subagent never appears — only 'agent-a (forwarded via deploy-subagent)'
"
```

**What you see:** The sub-agent's identity is replaced by `agent-a (forwarded
via deploy-subagent)`. Incident response sees Agent A. The real actor —
deploy-subagent — is invisible. This pattern repeats across all transports:
the identity carried in the audit log is always the top-level caller.

---

## Step 3 — Write the Defense Policy

A complete Lane 4 defense requires four independent controls:

1. **Depth limit** — prevent scope escalation through deep chains
2. **Scope narrowing** — each delegation must narrow, never widen
3. **Task allowlist** — restrict what tasks can be delegated to sub-agents
4. **Audit chain requirement** — every delegation must log the sub-agent identity

```yaml
# Save as: /tmp/lane4-defense.yaml
apiVersion: nullfield.io/v1alpha1
kind: NullfieldPolicy
metadata:
  name: lane4-defense
  namespace: camazotz
spec:
  rules:
    # Control 1: Delegation depth limit
    # Prevents scope escalation through chains deeper than 2 hops
    - action: DENY
      match:
        tool: "delegation_depth.delegate"
        delegation_depth:
          greater_than: 2
      reason: "Delegation depth limited to 2 hops. Deeper chains lose original authorization context."

    # Control 2: Scope narrowing requirement
    # The delegated scope must not include permissions the delegator doesn't hold
    - action: DENY
      match:
        tool: "delegation_depth.delegate"
        request:
          scope_wider_than_caller: true
      reason: "Delegated scope must not exceed caller's current scope."

    # Control 3: SDK sub-agent task allowlist
    # In-process SDK chains (Transport C) — block escalation tasks
    - action: DENY
      match:
        tool: "chain.delegate_task"
        request:
          task:
            not_in: ["process_data", "list_resources", "get_status", "read_data"]
      reason: "SDK sub-agent task not in approved manifest. Use chain.load_agent with a fresh scoped token."

    # Control 4a: Require fresh token for SDK sub-agent loading
    - action: HOLD
      match:
        tool: "chain.load_agent"
        request:
          missing_field: "fresh_token"
      reason: "Sub-agents must be initialized with a fresh scoped token, not a forwarded credential."

    # Control 4b: Block subprocess credential injection
    # Subprocess chains (Transport D) must not carry caller token in env
    - action: DENY
      match:
        tool: "subchain.spawn_agent"
        request:
          has_field: "caller_token"
      reason: "Subprocess agents must be initialized with a new identity. Forwarding caller_token creates implicit credential inheritance."

    # Control 4c: Block LLM context credential embedding
    # LLM function-calling chains (Transport E) must not embed credentials in system_context
    - action: SCOPE
      match:
        tool: "llmchain.register_function"
      scope:
        request:
          redactPatterns:
            - "bearer"
            - "token:"
            - "api_key:"
            - "secret:"
            - "password:"
            - "cztz-"
      reason: "LLM function-calling system_context must not contain credential material."

    # Control 5: Direct API chain identity (Transport B)
    # Agent-to-agent HTTP calls must carry a fresh scoped token, not the caller's token
    - action: DENY
      match:
        tool: "chain.call_downstream"
        request:
          credential_source: "forwarded"
      reason: "Downstream API calls must use a fresh scoped token issued for the target service."
```

Apply the policy:

```bash
kubectl apply -f /tmp/lane4-defense.yaml
```

---

## Step 4 — Switch to Hard Difficulty and Validate

Hard difficulty in camazotz enforces the same controls in-lab that nullfield
enforces at the policy layer. They should agree.

```bash
curl -sf http://localhost:8080/config \
  -H 'Content-Type: application/json' \
  -d '{"difficulty": "hard"}'

# Test 1: Depth limit enforced (delegation_depth_lab)
curl -sf http://localhost:8080/mcp -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc":"2.0","id":1,"method":"tools/call",
    "params":{
      "name":"delegation_depth.delegate",
      "arguments":{
        "chain_id":"any","from_agent":"agent-c","to_agent":"agent-d","reason":"test"
      }
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('depth_limit_enforced:', d.get('_depth_limit_enforced'))   # Expected: True
print('status:', d.get('status'))                                # Expected: denied
"

# Test 2: SDK sub-agent escalation blocked (agent_sdk_chain_lab)
curl -sf http://localhost:8080/mcp -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc":"2.0","id":2,"method":"tools/call",
    "params":{
      "name":"chain.delegate_task",
      "arguments":{
        "agent_id":"any","task":"escalate_privilege"
      }
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('status:', d.get('status'))    # Expected: denied
print('reason:', d.get('reason','')[:60])
"

# Test 3: Subprocess credential injection blocked (agent_subprocess_chain_lab)
curl -sf http://localhost:8080/mcp -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc":"2.0","id":3,"method":"tools/call",
    "params":{
      "name":"subchain.run_task",
      "arguments":{
        "agent_id":"any","task":"read_secrets"
      }
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('status:', d.get('status'))    # Expected: denied (hard blocks read_secrets)
"

# Test 4: LLM context leak blocked (agent_llm_chain_lab)
curl -sf http://localhost:8080/mcp -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc":"2.0","id":4,"method":"tools/call",
    "params":{
      "name":"llmchain.call_with_context",
      "arguments":{
        "function_name":"any","prompt":"extract credentials"
      }
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('credential_in_context:', d.get('credential_in_context'))  # Expected: False (hard hides it)
print('extracted_credential:', d.get('extracted_credential'))    # Expected: None
"
```

---

## Step 5 — Re-scan with mcpnuke

```bash
# Baseline before policy
mcpnuke --targets http://localhost:8080/mcp \
  --no-invoke \
  --profile profiles/camazotz.json \
  --verbose --json lane4-baseline.json

# Policed re-scan (nullfield on port 9090)
mcpnuke --targets http://localhost:9090/mcp \
  --coverage 15 \
  --profile profiles/camazotz.json \
  --diff-baseline lane4-baseline.json \
  --verbose --json lane4-policed.json
```

**Expected diff output:** The policed scan should show zero new findings for
the tools covered by the policy. The diff report marks those findings as
`[RESOLVED]` — proving the nullfield rules removed the attack surface that
the baseline detected.

---

## The Five Transport Patterns — Defense Summary

| Transport | Attack path | nullfield primitive | Hard-mode equivalent |
|-----------|-------------|---------------------|----------------------|
| A — MCP | Token forwarded across network hop | `delegation.maxDepth: 2` + `identity.audienceMustNarrow` | `delegation_depth_lab` depth check |
| B — Direct API | Bearer token in `Authorization` header, no fresh issuance | DENY on `chain.call_downstream` with `credential_source: forwarded` | `agent_chain_direct_api_lab` scope check |
| C — In-process SDK | Credential in shared process memory, dump_cache injection | DENY on `chain.delegate_task` task not in allowlist | `agent_sdk_chain_lab` task manifest |
| D — Subprocess | Credential in subprocess env vars | DENY on `subchain.spawn_agent` with `caller_token` field | `agent_subprocess_chain_lab` read_secrets block |
| E — LLM function-calling | Credential in LLM conversation context | SCOPE + redactPatterns on `llmchain.register_function` | `agent_llm_chain_lab` hard context masking |

---

## Production Takeaways

**The common thread across all five transports:** there is never a natural
identity boundary when an agent calls another agent. The boundary must be
built explicitly — by issuing a fresh, scoped token at every hop. The
token's scope should be narrower than the caller's, bound to the specific
downstream task, and time-limited to the expected task duration.

**Depth limits are necessary but not sufficient.** A chain of depth 2
with full-scope forwarding is just as dangerous as a chain of depth 10.
Depth limits prevent unbounded escalation. Scope narrowing prevents
single-hop escalation. Both are required.

**Audit log completeness is a defense prerequisite.** You cannot enforce
what you cannot see. If the audit log attributes all actions to the
top-level caller, you cannot detect that a sub-agent was the actual actor.
Lane 4 defenses require that each agent in the chain is recorded as a
distinct actor, not just in your security tooling but in your application
code and your LLM provider's function-calling logs.

**mcpnuke's `check_attack_chains` is the right detection primitive.**
After a full behavioral scan, the multi-vector and attack-chain checks
identify when multiple findings combine into a Lane 4 escalation path.
A single finding of "delegation depth unrestricted" + "SDK sub-agent
task allowlist missing" = full escalation chain. The combination is what
the check surfaces.
