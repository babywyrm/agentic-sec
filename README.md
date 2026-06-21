# agentic-security

Security architecture for agentic AI infrastructure — MCP tool execution, machine identity, and automated defense.

A documentation hub and cross-project reference for a closed-loop security stack protecting AI-agent deployments built on the [Model Context Protocol (MCP)](https://modelcontextprotocol.io). Four core tools, one shared vocabulary, one feedback loop.

<p align="center">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <a href="https://github.com/babywyrm/camazotz"><img alt="camazotz" src="https://img.shields.io/badge/camazotz-52%20labs-fb923c"></a>
  <a href="https://github.com/babywyrm/nullfield"><img alt="nullfield" src="https://img.shields.io/badge/nullfield-5%20actions-a78bfa"></a>
  <a href="https://github.com/babywyrm/mcpnuke"><img alt="mcpnuke" src="https://img.shields.io/badge/mcpnuke-scan%20%2B%20generate-34d399"></a>
  <a href="https://github.com/babywyrm/stoneburner"><img alt="stoneburner" src="https://img.shields.io/badge/stoneburner-15%20adversarial-ef4444"></a>
  <a href="https://github.com/babywyrm/skillseraph"><img alt="skillseraph" src="https://img.shields.io/badge/skillseraph-11%20platforms-8b5cf6"></a>
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
| See what's mature, thin, and planned next | [`docs/roadmap.md`](docs/roadmap.md) |

---

## The Tools

| Tool | Role | What it does |
|------|------|-------------|
| **[camazotz](https://github.com/babywyrm/camazotz)** | Vulnerable target | Intentionally vulnerable MCP server — 52 labs across 5 identity lanes and 5 transport surfaces, covering every OWASP MCP Top 10 risk |
| **[nullfield](https://github.com/babywyrm/nullfield)** | Policy arbiter | Sidecar proxy that intercepts every MCP `tools/call` and enforces ALLOW / DENY / HOLD / SCOPE / BUDGET policy before forwarding |
| **[mcpnuke](https://github.com/babywyrm/mcpnuke)** | Scanner | Outside-in MCP security scanner — static, behavioral, and AI-assisted probes; outputs findings + nullfield policy |
| **[stoneburner](https://github.com/babywyrm/stoneburner)** | Benchmarking + LLM eval | Provider benchmarking (cost, latency, accuracy) plus adversarial resilience testing (15 fixtures), red/blue security capability eval, security-architecture review benchmarking (`archreview`), and live infrastructure probing — with multi-judge consensus and multi-pass variance |
| **[skillseraph](https://github.com/babywyrm/skillseraph)** | Config scanner | Static analyzer for the agentic control plane — scans `AGENTS.md`, `SKILL.md`, rules, hooks, and MCP configs across 11 platforms for poisoning, injection, and supply-chain tampering. Covers [Attack Path Atlas](docs/attack-path-atlas.md) Domain J |
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
| [`docs/walkthroughs/model-compatibility-for-agentic-challenges.md`](docs/walkthroughs/model-compatibility-for-agentic-challenges.md) | Why AI-backed challenges need two-layer model validation — function-compatible vs walkthrough-compatible, and why a "safer" model can break a challenge |

### Tool Reference

| Document | What it covers |
|----------|---------------|
| [`docs/reference/camazotz.md`](docs/reference/camazotz.md) | Lab categories, difficulty levels, deployment options, API |
| [`docs/reference/nullfield.md`](docs/reference/nullfield.md) | The five actions, policy YAML, per-lane templates, CRDs |
| [`docs/reference/mcpnuke.md`](docs/reference/mcpnuke.md) | Scan modes, coverage flags, diff system, profile system, AI analysis |
| [`docs/reference/stoneburner.md`](docs/reference/stoneburner.md) | Providers, eval suites, adversarial/red-blue/probe commands, thinking mode, camazotz integration |

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
| 8 | [Beyond MCP](docs/walkthroughs/beyond-mcp.md) | Same attacks across LangChain, OpenAI Assistants, and CLI agents — not just MCP | 30m |
| 9 | [AI Governance Infrastructure as Attack Surface](docs/walkthroughs/ai-governance-infrastructure.md) | How AI governance gates can be bypassed structurally via open redirect — not prompt injection | 45m |
| 10 | [Token Cross-Pollution and Shared Identity](docs/walkthroughs/token-cross-pollution.md) | Shared IdP scope pollution (MCP-T42) + DPoP key leak forgery (MCP-T43) — two controls that fail together | 15m |
| 11 | [Building a Lane 4 Defense from Scratch](docs/walkthroughs/lane4-defense.md) | Depth limits, scope narrowing, task allowlists, and audit chain across all five Lane 4 transport patterns | 20m |
| 12 | [AI Guardrail Resistance Testing](docs/walkthroughs/guardrail-resistance-testing.md) | Systematically test whether AI-mediated security gates enforce protections or merely suggest them (MCP-T56) with `mcpnuke --inference` + stoneburner | 30m |

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
[stoneburner](https://github.com/babywyrm/stoneburner/blob/main/LICENSE) ·
[agentic-sec](./LICENSE)
