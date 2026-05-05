# Walkthrough 1: The Attack

Scan an MCP server, understand the findings, and map attack chains.

**Time:** 10 minutes
**Tested on:** Docker Compose (localhost:8080), K3s cluster (<NODE_IP>:30080)

---

## Step 1: Run the Scan

### Local (Docker Compose)

```bash
$ mcpnuke --targets http://localhost:8080/mcp --fast --no-invoke --verbose
```

### Kubernetes (through nullfield sidecar)

```bash
$ mcpnuke --targets http://<NODE_IP>:30080/mcp --fast --no-invoke --verbose
```

Both paths produce the same findings — nullfield passes `tools/list` through,
so mcpnuke sees the full tool surface.

## Step 2: Understand the Output

The scan discovers the MCP server and enumerates its tools:

```
▶ http://localhost:8080/mcp
  ✓ Transport=HTTP  post_url=http://localhost:8080/mcp
  Server: camazotz-brain-gateway v0.2.0  protocol=2025-03-26
  Tools (74):
      hallucination.execute_plan: Describe a maintenance task...
      shadow.register_webhook: Register a webhook callback URL...
      relay.execute_with_context: Execute a task using stored context...
      secrets.leak_config: Return current service configuration...
      ...
  --fast: sampled 5/74 security-relevant tools
```

`--fast` mode automatically selects the 5 most security-relevant tools based
on name, description, and parameter analysis. The tool scoring algorithm
prioritizes execution, credential, webhook, and admin capabilities.

## Step 3: Read the Findings

```
Per-Target Summary

  Target               Transport   Tools   Findings   Score   Time
  localhost:8080/mcp   HTTP            5         34     307   0.6s

  CRITICAL: 24  |  HIGH: 9  |  MEDIUM: 1  |  LOW: 0
```

34 findings across 4 severity levels. Key findings:

| Finding | Severity | Tool | What It Means |
|---------|----------|------|--------------|
| `prompt_injection` | CRITICAL | resource `config://system_prompt` | Tool definition contains LLM-interpretable instructions |
| `code_execution` | CRITICAL | `hallucination.execute_plan` | Tool accepts natural language that triggers code execution |
| `remote_access` | CRITICAL | `hallucination.execute_plan` | Tool can interact with filesystem/network |
| `webhook_persistence` | HIGH | `shadow.register_webhook` | Tool registers callbacks to external URLs |
| `token_theft` | HIGH | `relay.execute_with_context` | Tool accepts credential parameters |
| `config_tampering` | CRITICAL | `shadow.register_webhook` | Tool can modify server behavior |
| `exfil_flow` | CRITICAL | `shadow.register_webhook` | Data can flow from sensitive tools to external endpoints |

## Step 4: Map Attack Chains

mcpnuke detects multi-step attack sequences where one finding enables another:

```
Attack Chains Detected:
  ⚠  prompt_injection → code_execution (hallucination.execute_plan)
  ⚠  prompt_injection → token_theft (relay.execute_with_context)
  ⚠  code_execution → token_theft (hallucination.execute_plan, relay.execute_with_context)
  ⚠  code_execution → remote_access (hallucination.execute_plan)
  ⚠  config_tampering → code_execution (hallucination.execute_plan, shadow.register_webhook)
  ⚠  webhook_persistence → token_theft (relay.execute_with_context, shadow.register_webhook)
  ⚠  exfil_flow → token_theft (relay.execute_with_context, shadow.register_webhook)
  ⚠  exfil_flow → remote_access (hallucination.execute_plan, shadow.register_webhook)
  ⚠  config_tampering → webhook_persistence (shadow.register_webhook)
```

**Reading attack chains:** `A → B (tool1, tool2)` means finding A on tool1
enables finding B on tool2. The attacker chains these: inject a prompt →
execute code → steal tokens → exfiltrate via webhook.

Three tools appear in every chain: `hallucination.execute_plan`,
`shadow.register_webhook`, and `relay.execute_with_context`. These are the
critical targets for policy rules.

## Step 5: Save Baseline

```bash
$ mcpnuke --targets http://localhost:8080/mcp --fast --no-invoke \
    --save-baseline baseline.json --json report.json
```

The baseline enables regression testing — after applying defenses, re-scan
and compare to prove findings are resolved.

---

**Next:** [Walkthrough 2: The Defense](defense.md) — generate policy from these
findings and prove the attacks are blocked.
