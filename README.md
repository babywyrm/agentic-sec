# agentic-security

Security architecture for agentic AI infrastructure — MCP tool execution, machine identity, and automated defense.

A documentation hub and cross-project reference for a closed-loop security stack protecting AI-agent deployments built on the [Model Context Protocol (MCP)](https://modelcontextprotocol.io). Three tightly-coupled tools, one shared vocabulary, one feedback loop.

<p align="center">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <a href="https://github.com/babywyrm/camazotz"><img alt="camazotz" src="https://img.shields.io/badge/camazotz-39%20labs-fb923c"></a>
  <a href="https://github.com/babywyrm/nullfield"><img alt="nullfield" src="https://img.shields.io/badge/nullfield-5%20actions-a78bfa"></a>
  <a href="https://github.com/babywyrm/mcpnuke"><img alt="mcpnuke" src="https://img.shields.io/badge/mcpnuke-scan%20%2B%20generate-34d399"></a>
</p>

---

## Start Here

MCP and agentic AI patterns are 1–2 year old RFCs — the security conventions are still forming. If you know security but are new to this space, read the bridge document first. It maps your existing knowledge to the new threat model before you touch the labs or tooling.

| I want to… | Go here |
|---|---|
| Understand how MCP/agentic security differs from API security | [`docs/bridge.md`](docs/bridge.md) — *read this first* |
| Follow a structured curriculum | [`docs/learning-path.md`](docs/learning-path.md) |
| Run a full deployment scenario (bot, CI/CD, code review, SaaS) | [`docs/campaigns/`](docs/campaigns/README.md) |
| Attack a vulnerable MCP server | [Walkthrough 1 — The Attack](docs/walkthroughs/attack.md) |
| Defend with nullfield policy | [Walkthrough 2 — The Defense](docs/walkthroughs/defense.md) |
| Run the full scan → enforce → validate loop | [Walkthrough 5 — Live Feedback Loop](docs/walkthroughs/live-loop.md) |
| Understand the full architecture | [`docs/ecosystem.md`](docs/ecosystem.md) |

---

## The Three Tools

| Tool | Role | What it does |
|------|------|-------------|
| **[camazotz](https://github.com/babywyrm/camazotz)** | Vulnerable target | Intentionally vulnerable MCP server — 39 labs across 5 identity lanes and 5 transport surfaces, covering every OWASP MCP Top 10 risk |
| **[nullfield](https://github.com/babywyrm/nullfield)** | Policy arbiter | Sidecar proxy that intercepts every MCP `tools/call` and enforces ALLOW / DENY / HOLD / SCOPE / BUDGET policy before forwarding |
| **[mcpnuke](https://github.com/babywyrm/mcpnuke)** | Scanner | Outside-in MCP security scanner — static, behavioral, and AI-assisted probes; outputs findings + nullfield policy |

Each tool ships independently. They are more powerful together.

---

## The Problem

AI agents call tools. Tools have side effects. The AI cannot be trusted to make authorization decisions.

Every `tools/call` in an MCP deployment is a function invocation triggered by an LLM. That LLM can be manipulated by prompt injection, confused-deputy attacks, and social engineering — yet most MCP servers forward tool calls unconditionally. There is no policy layer, no identity verification, and no audit trail.

Three foundational failures compound:

1. **LLM guardrails are advisory, not enforceable.** The model can warn about a dangerous action while the tool executes it.
2. **Static API keys provide no identity.** You cannot distinguish a human operator from a compromised agent from a replayed token.
3. **Tool execution has no policy layer.** Without an arbiter, any registered tool call is forwarded unconditionally.

The defense stack here addresses all three. See [`docs/ecosystem.md`](docs/ecosystem.md) for the full architecture.

---

## The Feedback Loop

Scan → Recommend → Enforce → Validate. One script, one cycle:

```bash
# Local — generates policy, does not apply
./scripts/feedback-loop.sh http://localhost:8080/mcp

# Kubernetes — applies as NullfieldPolicy CRD, hot-reloads the sidecar
./scripts/feedback-loop.sh http://<NODE_IP>:30080/mcp --k8s camazotz

# With Claude AI analysis
ANTHROPIC_API_KEY=sk-ant-... ./scripts/feedback-loop.sh http://localhost:8080/mcp --claude
```

Detail in [`docs/feedback-loop.md`](docs/feedback-loop.md).

---

## Quick Start

```bash
# 1. Start the vulnerable target
git clone https://github.com/babywyrm/camazotz && cd camazotz
make env && make up

# 2. Scan it
pip install mcpnuke
mcpnuke --targets http://localhost:8080/mcp --fast --no-invoke --verbose

# 3. Generate a nullfield policy from the findings
mcpnuke --targets http://localhost:8080/mcp --fast --no-invoke --generate-policy fix.yaml

# 4. Close the loop
./scripts/feedback-loop.sh http://localhost:8080/mcp
```

For Kubernetes, Helm, and Teleport deployment options see [`docs/deployment-guide.md`](docs/deployment-guide.md).

---

## Documentation

### Architecture & Reference

| Document | What it covers |
|----------|---------------|
| [`docs/bridge.md`](docs/bridge.md) | MCP security for practitioners who know API security — what transfers, what doesn't |
| [`docs/ecosystem.md`](docs/ecosystem.md) | Full architecture — defense layers, data flows, identity lanes, coverage matrix |
| [`docs/identity-flows.md`](docs/identity-flows.md) | Five identity lanes × five transport surfaces — the foundational taxonomy |
| [`docs/golden-path.md`](docs/golden-path.md) | Production security architecture for MCP deployments — for security review boards |
| [`docs/feedback-loop.md`](docs/feedback-loop.md) | The scan → recommend → enforce → validate operational cycle |

### Tool Reference

| Document | What it covers |
|----------|---------------|
| [`docs/reference/camazotz.md`](docs/reference/camazotz.md) | Lab categories, difficulty levels, deployment options, API |
| [`docs/reference/nullfield.md`](docs/reference/nullfield.md) | The five actions, policy YAML, per-lane templates, CRDs |
| [`docs/reference/mcpnuke.md`](docs/reference/mcpnuke.md) | Scan modes, coverage flags, diff system, profile system, AI analysis |

### Deployment

| Guide | What it covers |
|-------|---------------|
| [`docs/deployment-guide.md`](docs/deployment-guide.md) | Local, cluster, and cloud — Docker Compose, Helm, K8s, brain providers |
| [`docs/teleport/setup.md`](docs/teleport/setup.md) | Machine identity for agents — tbot, K8s access, MCP App Access |

---

## Walkthroughs

| # | Walkthrough | What you'll do | Time |
|---|------------|---------------|------|
| 1 | [The Attack](docs/walkthroughs/attack.md) | Scan camazotz with mcpnuke, understand findings, map attack chains | 30m |
| 2 | [The Defense](docs/walkthroughs/defense.md) | Generate a nullfield policy, apply it, re-scan to confirm | 45m |
| 3 | [Lab Practice](docs/walkthroughs/practice.md) | camazotz defense-mode labs — policy, redaction, budget tuning | 60m |
| 4 | [AI-Powered Scanning](docs/walkthroughs/ai-powered-scanning.md) | Wire Claude into mcpnuke and camazotz — deep reasoning over findings | 45m |
| 5 | [Live Feedback Loop](docs/walkthroughs/live-loop.md) | Automated scan → generate → apply → validate with one script | 20m |
| 6 | [Delegation Chain Attacks](docs/walkthroughs/delegation-chains.md) | Multi-agent identity dilution — Agent A → B → C loses authorization | 45m |
| 7 | [Flow Types in Practice](docs/walkthroughs/flow-types-in-practice.md) | All five lanes end-to-end with `--by-lane` + `--coverage-report` | 60m |

---

## Who This Is For

**Security engineers** evaluating how to protect MCP deployments in production Kubernetes — start with [Golden Path](docs/golden-path.md).

**Red team operators** testing MCP server defenses — start with [Walkthrough 1](docs/walkthroughs/attack.md).

**Blue team defenders** learning nullfield policy authoring — start with [Walkthrough 2](docs/walkthroughs/defense.md).

**Platform engineers** building agentic infrastructure — start with the [Deployment Guide](docs/deployment-guide.md).

---

## Roadmap

See [`docs/ecosystem.md#roadmap`](docs/ecosystem.md#roadmap--how-this-grows) for the full roadmap with implementation status.

---

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md).

---

## License

MIT. Each sibling project is independently MIT-licensed.
[camazotz](https://github.com/babywyrm/camazotz/blob/main/LICENSE) ·
[nullfield](https://github.com/babywyrm/nullfield/blob/main/LICENSE) ·
[mcpnuke](https://github.com/babywyrm/mcpnuke/blob/main/LICENSE) ·
[agentic-sec](./LICENSE)
