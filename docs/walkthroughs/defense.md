# Walkthrough 2: The Defense

Generate nullfield policy from scan findings, apply it, and prove the
attacks are blocked.

**Time:** 15 minutes
**Prerequisites:** Walkthrough 1 completed, nullfield available (compose or K8s)

---

## Step 1: Generate Policy

```bash
mcpnuke --targets http://localhost:8080/mcp --fast --no-invoke \
  --generate-policy fix.yaml
```

Open `fix.yaml` — mcpnuke mapped each finding to a nullfield action:

```yaml
rules:
  - action: DENY
    toolNames: ["hallucination.execute_plan"]
    reason: "mcpnuke: remote access capability"

  - action: DENY
    toolNames: ["shadow.register_webhook"]
    reason: "mcpnuke: webhook persistence vector"

  - action: SCOPE
    toolNames: ["relay.execute_with_context"]
    reason: "mcpnuke: credential parameter exposure"
    scope:
      response:
        redactPatterns: ["password", "secret", "token", "api_key"]

  - action: DENY
    toolNames: ["*"]
    reason: "mcpnuke: default deny"
```

The logic: dangerous tools get DENY or HOLD. Leaky tools get SCOPE (redaction).
Everything else gets default deny.

## Step 2: Review and Refine

The generated policy is a starting point. You might want to:

- Change DENY to HOLD for tools you want to allow with human approval
- Add ALLOW rules for tools you trust
- Add BUDGET rules for expensive tools
- Tune SCOPE redaction patterns

For example, if `cost.check_usage` should be allowed:

```yaml
  - action: ALLOW
    toolNames: ["cost.check_usage"]
    reason: "read-only cost check, safe"
```

Insert it before the default deny rule.

## Step 3: Apply the Policy

### Docker Compose

```bash
cp fix.yaml examples/policy.yaml
docker compose restart nullfield
```

### Kubernetes (CRD)

```bash
kubectl apply -f deploy/crds/          # one-time
kubectl apply -f fix.yaml              # apply policy
```

### Kubernetes (ConfigMap)

```bash
kubectl -n camazotz create configmap nullfield-config \
  --from-file=policy.yaml=fix.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
```

The sidecar hot-reloads within 30 seconds.

## Step 4: Re-scan

```bash
mcpnuke --targets http://localhost:8080/mcp --fast --no-invoke --verbose
```

What you should see:
- Tools that were DENY'd now return `-32000` or `-32003` errors
- Tools that were SCOPE'd still return data but with credentials redacted
- The finding count drops (tools blocked by nullfield can't be exploited)

### Compare Against Baseline

```bash
mcpnuke --targets http://localhost:8080/mcp --fast --no-invoke \
  --baseline before-fix.json
```

New findings = regressions. Removed findings = fixes that worked.

## Step 5: Verify Specific Tools

Test a denied tool:

```bash
curl -s -X POST http://localhost:9090 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"shadow.register_webhook","arguments":{"url":"https://evil.com"}}}'
```

Expected: `{"error":{"code":-32000,"message":"denied by policy: mcpnuke: webhook persistence vector"}}`

Test a scoped tool:

```bash
curl -s -X POST http://localhost:9090 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"relay.execute_with_context","arguments":{"task":"check status","context_keys":["db"]}}}'
```

Expected: response with credentials replaced by `[REDACTED]`.

## What's Next

[Walkthrough 3: Lab Practice](practice.md) — write policy by hand in the
defense-mode labs.
