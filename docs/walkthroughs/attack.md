# Walkthrough 1: The Attack

Scan an MCP server, understand the findings, and map attack chains.

**Time:** 10 minutes
**Prerequisites:** camazotz running locally (`make up` or Docker Compose)

---

## Step 1: Run the Scan

```bash
mcpnuke --targets http://localhost:8080/mcp --fast --no-invoke --verbose
```

This performs static analysis on all MCP tools without invoking them.
Safe for any environment.

## Step 2: Read the Findings

The scan produces findings grouped by severity:

```
CRITICAL: 24  |  HIGH: 9  |  MEDIUM: 1  |  LOW: 0
```

Each finding has:
- **Check name** — what mcpnuke tested (e.g., `prompt_injection`, `code_execution`)
- **Severity** — CRITICAL, HIGH, MEDIUM, LOW
- **Title** — what was found
- **Tool** — which MCP tool is affected

Key finding types to understand:

| Finding | What it means | Real-world risk |
|---------|--------------|-----------------|
| `prompt_injection` | Tool definition contains text an LLM would interpret as instructions | Attacker controls what the AI does |
| `code_execution` | Tool accepts code/command parameters | Attacker runs arbitrary code |
| `webhook_persistence` | Tool registers callbacks to external URLs | Attacker maintains persistence |
| `token_theft` | Tool accepts or exposes credential parameters | Attacker steals tokens |
| `exfil_flow` | Tool can send data to attacker-controlled endpoints | Data exfiltration |
| `config_tampering` | Tool can modify server configuration | Attacker changes behavior |

## Step 3: Understand Attack Chains

mcpnuke detects multi-step attack sequences:

```
Attack chain: prompt_injection → code_execution (hallucination.execute_plan)
Attack chain: webhook_persistence → token_theft (relay.execute_with_context, shadow.register_webhook)
```

An attack chain means: finding A enables finding B. The attacker uses prompt
injection to trigger code execution, or uses webhook persistence to exfiltrate
stolen tokens.

## Step 4: Save for Comparison

```bash
mcpnuke --targets http://localhost:8080/mcp --fast --no-invoke \
  --save-baseline before-fix.json \
  --json report.json
```

You now have a baseline to compare against after applying defenses.

## What's Next

[Walkthrough 2: The Defense](defense.md) — generate a nullfield policy from
these findings and prove the attacks are blocked.
