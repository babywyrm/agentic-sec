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
| Fast | `--fast` | Top 5 security-relevant tools, skip slow probes. Alias for `--coverage 5` |
| Coverage-limited | `--coverage N` | Sample top N security-relevant tools. `--coverage 0` = all tools |
| Full | *(default)* | All tools, all probes, behavioral analysis |
| AI-assisted | `--claude` | Claude reasons about findings — Phase 1 (schema), Phase 2 (live invocation), Phase 3 (chain reasoning) |
| Deterministic | `--deterministic` | Stable ordering for benchmarking |

## Key Commands

```bash
# Static baseline — all 99 tools, zero API calls, instant
mcpnuke --targets http://localhost:8080/mcp \
  --no-invoke --coverage 0 --verbose \
  --json baseline.json

# Coverage-limited AI scan — top 15 tools, all three Claude phases
mcpnuke --targets http://localhost:8080/mcp \
  --coverage 15 --claude --claude-model claude-sonnet-4-20250514 \
  --verbose --json deep.json

# Diff the AI scan against the static baseline
mcpnuke diff baseline.json deep.json
# or as part of the same scan:
mcpnuke --targets http://localhost:8080/mcp \
  --coverage 15 --claude \
  --diff-baseline baseline.json \
  --json deep.json

# Profile-enriched scan — better lane/transport attribution and AI prompt quality
mcpnuke --targets http://localhost:8080/mcp \
  --coverage 15 --claude \
  --profile profiles/camazotz.json \
  --json report.json

# Generate nullfield policy from findings
mcpnuke --targets http://localhost:8080/mcp --fast --no-invoke --generate-policy fix.yaml

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

## Coverage & Diff

The `--coverage N` flag controls how many tools are sampled, letting you dial between speed and depth without changing anything else.

| Command | Tools | Time | Use case |
|---------|-------|------|----------|
| `--fast` | top 5 | ~2s | CI gate, quick PR check |
| `--coverage 15` | top 15 | ~3 min | Sprint security review |
| `--coverage 0` (default) | all | varies | Full assessment |

**Diff workflow** — compare a cheap static baseline against a deep AI scan to see exactly what Claude added:

```bash
# 1. Run a static baseline (free, instant, all tools)
mcpnuke --targets http://$TARGET/mcp \
  --no-invoke --coverage 0 \
  --json baseline.json

# 2. Run a deep Claude scan against the top 15 tools
mcpnuke --targets http://$TARGET/mcp \
  --coverage 15 --claude --claude-model claude-sonnet-4-20250514 \
  --diff-baseline baseline.json \
  --json deep.json

# The diff block in deep.json (and printed to terminal) shows:
#   NEW (47):  findings only Claude's behavioral probes found
#   RESOLVED:  findings static analysis over-reported
#   46 unchanged finding(s) carried over.

# 3. Or run the diff separately at any time
mcpnuke diff baseline.json deep.json
```

The diff is also written into the JSON output under `targets[0].diff` so it can be consumed by CI pipelines or dashboards.

## Profile System

A profile file maps tool names to their identity lane, transport surface, OWASP MCP threat ID, and freeform notes. It's optional — mcpnuke works fully without one. With a profile, AI prompts get richer context and finding attribution is more precise.

```bash
# Use the bundled camazotz profile
mcpnuke --targets http://localhost:8080/mcp \
  --coverage 15 --claude \
  --profile profiles/camazotz.json

# Use the bundled DVMCP profile
mcpnuke --targets http://localhost:4567/mcp \
  --profile profiles/dvmcp.json
```

**Writing your own profile** — copy `profiles/example.json` and fill in your tool names:

```json
{
  "name": "my-target",
  "version": "1",
  "tools": [
    {
      "name": "create_ticket",
      "lane": 2,
      "transport": "A",
      "threat_id": "MCP-T02",
      "notes": "Confused deputy risk: acts on behalf of user without re-auth"
    }
  ]
}
```

Shipped profiles: `profiles/camazotz.json` (70+ tools), `profiles/dvmcp.json` (18 tools), `profiles/example.json` (annotated template).

## Check Categories

| Category | Checks | What They Find |
|----------|--------|---------------|
| Static | prompt_injection, code_execution, permissions, schemas | Dangerous tool definitions |
| Behavioral | rug_pull, injection, state_mutation, rate_limit | Runtime exploitation |
| Credential | token_theft, response_credentials, config_dump | Secret exposure |
| JWT boundary | `jwt_audience_target_match`, `jwt_cross_role_replay` | HIGH · Lane 1 — closes the MCP-T04 / Lane 1 audience-and-replay coverage gap (`mcpnuke/checks/jwt_boundary.py`) |
| Teleport | proxy_discovery, cert_validation, bot_overprivilege | Infrastructure misconfig |
| Exploit chains | bot_theft, role_escalation, cert_replay | Multi-step attack sequences |

## JSON Output Fields

Each target in `--json` output now includes:

| Field | Description |
|-------|-------------|
| `tools_total` | Total tools discovered on the server |
| `tools_scanned` | Tools actually analyzed (may be < total with `--coverage N`) |
| `tools_scanned_names` | Names of sampled tools |
| `tools_unscanned_count` | `tools_total - tools_scanned` |
| `findings[].taxonomy_id` | OWASP MCP threat ID (e.g. `MCP-T06`), extracted from AI title if not in structured field |
| `findings[].mitre_id` | MITRE ATT&CK ID (e.g. `T1059`) when present |
| `diff` | Present when `--diff-baseline` is used — contains `new`, `resolved`, `severity_changes`, `unchanged_count` |

## Policy Generation Mapping

| Finding Type | nullfield Action |
|-------------|-----------------|
| code_execution, remote_access | HOLD |
| webhook_persistence, exfil_flow | DENY |
| token_theft, credential_in_schema | SCOPE (redact) |
| rate_limit | BUDGET |
| prompt_injection + code_execution | HOLD (strict timeout) |
