# skillseraph Reference

> **Agent config security scanner** — static analysis of the agentic control plane

[GitHub](https://github.com/babywyrm/skillseraph) · v0.1.0 · 68 tests · 11 platforms

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

| Category | Detects | Taxonomy |
|----------|---------|----------|
| `injection` | Instruction override, persona hijack, jailbreak, token-boundary, hidden-comment | MCP-T01/T02 |
| `exfiltration` | Credential harvest, URL/DNS/clipboard exfil, secret-file & env access | MCP-T07/T12 |
| `permission_bypass` | Sandbox/approval bypass, arbitrary execution, privilege requests | MCP-T09 |
| `encoding` | Base64/hex blobs, data URIs, unicode-escape chains | MCP-T01 |
| `urls` | Known exfil services, metadata/loopback URLs, MCP server redirects | MCP-T06/T14 |
| `suppression` | Review/PR suppression, stealth operation, user deception | MCP-T13 |
| `persistence` | Cross-session behavior change, self-config modification, hook install | MCP-T14 |
| `tool_abuse` | Dangerous command invocation, path traversal, remote bootstrap | MCP-T06/T08/T09 |
| `authority_fabrication` | Fake maintenance windows, fabricated approvals, pre-authorization claims | MCP-T02 |
| `runtime_bypass` | Language-runtime evasion of command blocklists, encoded-pipe-to-shell | MCP-T05 |
| `breakglass` | Embedded override tokens, admission/policy bypass instructions | MCP-T09 |

Detection patterns are data-driven (`rules/*.yaml`) — adding a rule needs no code.

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
