# skillseraph Reference

> **Agent config security scanner** — static analysis of the agentic control plane

[GitHub](https://github.com/babywyrm/skillseraph) · v0.2.0 · 110 tests · 11 platforms

---

## Role in the Ecosystem

skillseraph scans the *config files* that tell an AI agent how to behave —
`AGENTS.md`, `SKILL.md`, `.cursor/rules`, hook configs, MCP server definitions —
for poisoning, injection, and supply-chain tampering.

Where the other tools target running systems, skillseraph targets the
control-plane artifacts at rest:

| Tool | Target | When |
|------|--------|------|
| **mcpnuke** | Live MCP endpoints | Runtime / CI against deployed services |
| **nullfield** | `tools/call` at runtime | Inline enforcement |
| **stoneburner** | The LLM itself | Adversarial benchmarking |
| **skillseraph** | Agent config files at rest | Pre-commit / PR / pre-boot |

It closes the gap covered by **Attack Path Atlas Domain J** (config & automation):
poisoned skills/rules/hooks, dependency-planted instructions, and review
suppression that never touch a live endpoint and so are invisible to mcpnuke.

---

## Platforms

Auto-detected from file patterns; restrict with `--platform`:

Cursor · Codex · GitHub Copilot · Claude · Windsurf · Cline/Continue · Devin ·
Bedrock Agents · LangChain/LangGraph · CrewAI/AutoGPT · generic agent configs.

---

## Detection categories

| Category | Detects | Taxonomy | Atlas |
|----------|---------|----------|-------|
| `injection` | Instruction override, persona hijack, jailbreak, token-boundary, hidden-comment, **sleeper/conditional-trigger payloads** | MCP-T01/T02 | J1, C1 |
| `exfiltration` | Credential harvest, URL/DNS/clipboard exfil, secret-file & env access | MCP-T07/T12 | J1 |
| `permission_bypass` | Sandbox/approval bypass, arbitrary execution, privilege requests | MCP-T09 | J1 |
| `encoding` | Base64/hex blobs, data URIs, unicode-escape chains, `eval(atob())`, ROT13/charcode obfuscation | MCP-T05 | J8 |
| `urls` | Known exfil services, metadata/loopback URLs, MCP server redirects | MCP-T06/T14 | J1 |
| `suppression` | Review/PR suppression, stealth operation, user deception | MCP-T13 | J7 |
| `persistence` | Cross-session behavior change, self-config modification, hook install | MCP-T14 | J4 |
| `tool_abuse` | Dangerous command invocation, path traversal, remote bootstrap, **supply-chain** (unpinned installs, postinstall hooks, registry confusion) | MCP-T04/T06/T08/T09 | J4, D1/D3/D4 |
| `authority_fabrication` | Fake maintenance windows, fabricated approvals, pre-authorization claims | MCP-T02 | J1 |
| `runtime_bypass` | Language-runtime evasion of command blocklists, encoded-pipe-to-shell | MCP-T05 | J4 |
| `breakglass` | Embedded override tokens, admission/policy bypass instructions | MCP-T09 | J1 |
| `mcp_servers` | Poisoned MCP server defs (remote/raw-IP URLs, env-credential injection, stdio exec, TLS disable, wildcard tools) + **tool-schema smuggling** | MCP-T01/T03/T06/T08/T09/T12/T14 | J3/J4, I3 |
| `automation_triggers` | Wildcard event triggers, shell exec in automations, broad write perms | MCP-T09 | J3 |
| `config_inheritance` | Parent traversal, absolute-path includes, remote config fetch, recursive globs | MCP-T02/T03 | J5 |
| `skill_invocation` | **Skill invocation hijack**: callback/redirect on invoke, self-modification, invocation-time override, silent invocation, remote skill pull | MCP-T01/T03/T08/T12/T13/T14 | J2 |

Detection patterns are data-driven (`rules/*.yaml`, 14 packs) — adding a rule
needs no code. Findings carry an OWASP MCP / MCP-T taxonomy ID and an Attack
Path Atlas domain ID (Domain J primary; cross-domain C1/I3/D where statically
detectable).

---

## Commands

```bash
skillseraph .                                   # auto-detect + scan
skillseraph . --platform cursor                 # focused
skillseraph . --no-deps                         # skip dependency trees
skillseraph . --fail-on high                    # CI gate (default)
skillseraph . --json-out f.json --sarif r.sarif # machine-readable
skillseraph . --save-baseline baseline.json     # accept current findings
skillseraph . --baseline baseline.json          # suppress accepted findings
```

Exit codes: `0` clean, `1` findings at/above `--fail-on`, non-zero on error.

---

## Integration

- **GitHub Actions** — composite `action.yml` + reusable `scan.yml` (SARIF upload)
- **Pre-commit** — local hook on agent-config file patterns
- **Kubernetes** — init-container gate on mounted config volumes
- **IDE hooks** — Cursor `beforeAgentStart` pre-session scan

See the [QUICKSTART](https://github.com/babywyrm/skillseraph/blob/main/QUICKSTART.md).

---

## Standards Alignment

- OWASP Top 10 for LLM Applications (LLM01 Prompt Injection)
- OWASP MCP Top 10 (MCP01–MCP10)
- agentic-sec [Attack Path Atlas](../attack-path-atlas.md) — Domain J
