# mcpnuke Quick Reference

MCP red teaming and security scanner.

**Repo:** [github.com/babywyrm/mcpnuke](https://github.com/babywyrm/mcpnuke) · v6.13.0 · 993 tests · 40/57 taxonomy IDs · MIT

**In the framework:** mcpnuke is the validator that exercises every cell of
the [Identity Flow Framework](../identity-flows.md). New checks should
declare which lane (1–5) and transport (A–E) they target in their
docstring. Transports D (subprocess) and E (native LLM function-calling)
were ratified 2026-04-28 — see
[camazotz ADR 0001](https://github.com/babywyrm/camazotz/blob/main/docs/adr/0001-five-transport-taxonomy.md)
for the full taxonomy.

## Recent work (2026-07 → 2026-08)

- **MCP 2026-07-28 stateless protocol** (`core/protocol.py`) — mcpnuke scans
  servers speaking the stateless spec alongside legacy handshake servers. See
  [Protocol Modes](#protocol-modes) below.
- **Quality hardening.** `ruff` strict at zero (370 → 0 violations) and `mypy` on
  a tightening ratchet (81 → 48), with `disallow_untyped_defs` enforced across
  `core/`. Credential and prompt-injection regexes were consolidated into single
  sources of truth (`patterns/credentials.py`, `patterns/rules.py`) after five
  divergent copies were found to disagree about what a secret looks like. The
  repo carries no `# type: ignore`.
- **CI runs for the first time.** The Tests workflow had been dying before pytest
  on every run; it now gates lint plus the full suite on Python 3.11, 3.12 and 3.13.
- **Docs restructured** — the README became a navigable front door and the
  reference material moved into `docs/`, with the CLI reference generated from
  the argument parser. See [Upstream Documentation](#upstream-documentation).

### Earlier: coverage pass (2026-06-28)

- **Taxonomy coverage:** 14/57 → **40/57 IDs (70%)**. Tier 1 is complete;
  remaining gaps are mostly multi-auth, RAG/governance, and transport identity
  dilution scenarios that require specialized fixtures.
- **New runtime/static checks:** MCP-T01 prompt injection via tool args, MCP-T02
  tool output poisoning, MCP-T03 credential forwarding, MCP-T05 broad command
  injection, MCP-T08 remote package execution, MCP-T10 agentic loops, MCP-T13
  unsigned inter-agent comms, MCP-T15 model routing, plus thin detectors for
  T17/T28/T32/T34/T35/T36/T52/T53/T57/T58.
- **Roadmap added:** `ROADMAP.md` tracks covered IDs, Tier 2 audit results, live
  targets, and infrastructure gaps.

## Protocol Modes

The 2026-07-28 spec retires the `initialize`/`initialized` handshake and the
`Mcp-Session-Id` header. mcpnuke speaks both dialects rather than choosing one.

| Mode | Flag | Behaviour |
|------|------|-----------|
| Auto | `--protocol-mode auto` *(default)* | Probes for whichever protocol the server speaks |
| Legacy | `--protocol-mode legacy` | `initialize`/`initialized` handshake, `Mcp-Session-Id` correlation |
| Stateless | `--protocol-mode stateless` | 2026-07-28 spec — routing headers, no session |

In stateless mode every request carries `Mcp-Method`, `Mcp-Name` and
`MCP-Protocol-Version` routing headers (SEP-2243), with CR/LF stripped so a
hostile tool name cannot smuggle additional headers, and client identity moves
into `params._meta` (`io.modelcontextprotocol/clientInfo`) in place of the
retired handshake. `Mcp-Session-Id` and `notifications/initialized` are sent in
legacy mode only, per SEP-2567.

Two consequences matter for scanning. `server/discover` is probed directly, and
an anonymous caller that can read server capabilities raises a Lane 5 /
Transport A finding, **"Unauthenticated MCP server/discover accepted"**. And
`TargetResult.protocol_mode` records what was negotiated, so a report says which
dialect the target actually spoke. HTTP+SSE stays on the legacy path
deliberately — the spec deprecates that transport with a twelve-month offramp.

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
# Static baseline — all 139 tools, zero API calls, instant
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

## CI Integration

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Clean scan — no findings at or above `--fail-on` threshold |
| `1` | At least one finding at or above threshold (default: HIGH) |
| `2` | Scanner error (target unreachable, invalid args, unhandled exception) |

### `--fail-on` severity gate

```bash
# Default: exit 1 on HIGH or CRITICAL
mcpnuke --targets http://target/mcp --fast

# Only fail on CRITICAL
mcpnuke --targets http://target/mcp --fast --fail-on critical

# Fail on anything (including LOW)
mcpnuke --targets http://target/mcp --fast --fail-on any

# Informational only — always exit 0
mcpnuke --targets http://target/mcp --fast --fail-on none
```

Choices: `critical`, `high` (default), `medium`, `low`, `any`, `none`.

### `--sarif` — SARIF 2.1.0 export

```bash
mcpnuke --targets http://target/mcp --fast --sarif results.sarif
```

Maps: CRITICAL/HIGH → `error`, MEDIUM → `warning`, LOW → `note`. Embeds
`security-severity` and taxonomy tags (`MCP-T06`, `T1059`, etc.) in SARIF
rule properties. Ready for GitHub Code Scanning upload:

```yaml
- name: Upload SARIF to GitHub Code Scanning
  uses: github/codeql-action/upload-sarif@v3
  if: always()
  with:
    sarif_file: results.sarif
```

See [CI/CD Integration Guide](https://github.com/babywyrm/mcpnuke/blob/main/docs/ci-cd-guide.md)
for full GitHub Actions, GitLab CI, and mcpnuke-runner (K8s) setup.

### Token redaction

Bearer tokens stored in `auth_context` via `--auth-token` are automatically
stripped from all JSON and SARIF output. The `_raw_token` field is redacted;
JWT claim summaries, introspection summaries, and JWKS summaries are preserved.

---

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
  --coverage-report http://$K8S_HOST:3000
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

Shipped profiles: `profiles/camazotz.json` (139 tools), `profiles/dvmcp.json` (18 tools), `profiles/example.json` (annotated template).

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

## Upstream Documentation

This page is a hub-level summary. mcpnuke's own `docs/` carries the full
reference, and `docs/cli-reference.md` is generated from the argument parser, so
it cannot drift from `--help`.

| Document | Contents |
|----------|----------|
| [`docs/cli-reference.md`](https://github.com/babywyrm/mcpnuke/blob/main/docs/cli-reference.md) | Every flag, grouped by concern — generated from the parser |
| [`docs/checks.md`](https://github.com/babywyrm/mcpnuke/blob/main/docs/checks.md) | All 59 registered checks plus 24 deep behavioral probes, with severities |
| [`docs/scan-modes.md`](https://github.com/babywyrm/mcpnuke/blob/main/docs/scan-modes.md) | Scan modes and fast-mode scoring |
| [`docs/methodology.md`](https://github.com/babywyrm/mcpnuke/blob/main/docs/methodology.md) | Behavioral probing, attack chain detection, risk scoring, DVMCP testing |
| [`docs/ai-analysis.md`](https://github.com/babywyrm/mcpnuke/blob/main/docs/ai-analysis.md) | Claude-backed analysis phases |
| [`docs/kubernetes.md`](https://github.com/babywyrm/mcpnuke/blob/main/docs/kubernetes.md) | In-cluster deployment and service discovery |
| [`docs/ci-cd-guide.md`](https://github.com/babywyrm/mcpnuke/blob/main/docs/ci-cd-guide.md) | GitHub Actions, GitLab CI, mcpnuke-runner |
