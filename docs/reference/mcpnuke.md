# mcpnuke Quick Reference

MCP red teaming and security scanner.

**Repo:** [github.com/babywyrm/mcpnuke](https://github.com/babywyrm/mcpnuke)

**In the framework:** mcpnuke is the validator that exercises every cell of
the [Identity Flow Framework](../identity-flows.md). New checks should
declare which lane (1–5) and transport (A–C) they target in their docstring.

## Scan Modes

| Mode | Flag | What It Does |
|------|------|-------------|
| Static only | `--no-invoke` | Analyze tool schemas without calling them |
| Fast | `--fast` | Top 5 security-relevant tools, skip slow probes |
| Full | *(default)* | All tools, all probes, behavioral analysis |
| AI-assisted | `--claude` | Claude reasons about findings |
| Deterministic | `--deterministic` | Stable ordering for benchmarking |

## Key Commands

```bash
# Basic scan
mcpnuke --targets http://localhost:8080/mcp --fast --no-invoke --verbose

# Generate nullfield policy from findings
mcpnuke --targets http://localhost:8080/mcp --fast --no-invoke --generate-policy fix.yaml

# Save baseline for regression testing
mcpnuke --targets http://localhost:8080/mcp --save-baseline baseline.json

# Compare against baseline
mcpnuke --targets http://localhost:8080/mcp --baseline baseline.json

# K8s service discovery
mcpnuke --k8s-discover --k8s-discover-namespaces camazotz --verbose

# With OAuth
mcpnuke --targets https://mcp.example.com/mcp \
  --oidc-url https://auth.example.com/realms/mcp \
  --client-id scanner --client-secret "$SECRET"
```

## Check Categories

| Category | Checks | What They Find |
|----------|--------|---------------|
| Static | prompt_injection, code_execution, permissions, schemas | Dangerous tool definitions |
| Behavioral | rug_pull, injection, state_mutation, rate_limit | Runtime exploitation |
| Credential | token_theft, response_credentials, config_dump | Secret exposure |
| Teleport | proxy_discovery, cert_validation, bot_overprivilege | Infrastructure misconfig |
| Exploit chains | bot_theft, role_escalation, cert_replay | Multi-step attack sequences |

## Policy Generation Mapping

| Finding Type | nullfield Action |
|-------------|-----------------|
| code_execution, remote_access | HOLD |
| webhook_persistence, exfil_flow | DENY |
| token_theft, credential_in_schema | SCOPE (redact) |
| rate_limit | BUDGET |
| prompt_injection + code_execution | HOLD (strict timeout) |
