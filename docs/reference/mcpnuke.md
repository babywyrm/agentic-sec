# mcpnuke Quick Reference

MCP red teaming and security scanner.

**Repo:** [github.com/babywyrm/mcpnuke](https://github.com/babywyrm/mcpnuke)

**In the framework:** mcpnuke is the validator that exercises every cell of
the [Identity Flow Framework](../identity-flows.md). New checks should
declare which lane (1–5) and transport (A–E) they target in their
docstring. Transports D (subprocess) and E (native LLM function-calling)
were ratified 2026-04-28 — see
[camazotz ADR 0001](https://github.com/babywyrm/camazotz/blob/main/docs/adr/0001-five-transport-taxonomy.md)
for the full taxonomy.

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

## Cross-Project Lane Reporting

| Flag | What It Does |
|------|-------------|
| `--by-lane` | Group findings by identity lane (1–5) with per-lane severity tallies and a `checks fired / checks defined` coverage fraction. |
| `--coverage-report <camazotz-url>` | Fetch `/api/lanes` (schema v1) from a camazotz target and emit a cross-project coverage report intersecting mcpnuke's finding catalog with camazotz's lane distribution. |
| `--generate-policy <fix.yaml>` | Emit a ready-to-apply nullfield policy YAML directly from findings — the bridge that makes the scan → recommend → enforce loop one command. |

```bash
# Per-lane breakdown of one scan
mcpnuke --targets http://localhost:8080/mcp --fast --by-lane

# Ecosystem-level coverage report against a live camazotz
mcpnuke --targets http://$K8S_HOST:30080/mcp \
  --coverage-report http://$K8S_HOST:8080
```

## Check Categories

| Category | Checks | What They Find |
|----------|--------|---------------|
| Static | prompt_injection, code_execution, permissions, schemas | Dangerous tool definitions |
| Behavioral | rug_pull, injection, state_mutation, rate_limit | Runtime exploitation |
| Credential | token_theft, response_credentials, config_dump | Secret exposure |
| JWT boundary | `jwt_audience_target_match`, `jwt_cross_role_replay` | HIGH · Lane 1 — closes the MCP-T04 / Lane 1 audience-and-replay coverage gap (`mcpnuke/checks/jwt_boundary.py`) |
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
