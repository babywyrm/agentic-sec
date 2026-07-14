# agentic-sec

**Security architecture for agentic AI — MCP tool execution, machine identity, and automated defense.**

A documentation hub and cross-project reference for a closed-loop security stack
that protects AI-agent deployments built on the
[Model Context Protocol (MCP)](https://modelcontextprotocol.io).

**Five tools · four lenses · one feedback loop.**

<p align="center">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
  <a href="https://github.com/babywyrm/camazotz"><img alt="camazotz" src="https://img.shields.io/badge/camazotz-52%20labs-fb923c"></a>
  <a href="https://github.com/babywyrm/nullfield"><img alt="nullfield" src="https://img.shields.io/badge/nullfield-5%20actions-a78bfa"></a>
  <a href="https://github.com/babywyrm/mcpnuke"><img alt="mcpnuke" src="https://img.shields.io/badge/mcpnuke-scan%20%2B%20generate-34d399"></a>
  <a href="https://github.com/babywyrm/stoneburner"><img alt="stoneburner" src="https://img.shields.io/badge/stoneburner-LLM%20eval-ef4444"></a>
  <a href="https://github.com/babywyrm/skillseraph"><img alt="skillseraph" src="https://img.shields.io/badge/skillseraph-11%20platforms-8b5cf6"></a>
</p>

---

## What this is

AI agents call tools; tools have side effects; the model cannot be trusted to
make authorization decisions. Every MCP `tools/call` is a function invocation an
LLM can be talked into via prompt injection, confused-deputy attacks, or social
engineering — yet most servers forward tool calls unconditionally, with no
policy layer, no identity, and no audit trail.

Three failures compound:

1. **LLM guardrails are advisory, not enforceable** — the model can warn about a
   dangerous action while the tool executes it.
2. **Static API keys carry no identity** — a human, a compromised agent, and a
   replayed token look identical.
3. **Tool execution has no policy layer** — without an arbiter, any registered
   call is forwarded unconditionally.

`agentic-sec` is the hub that ties together the tools, the shared vocabulary,
and the operational loop for defending that surface. New to MCP security but
know API security? Start with [`docs/bridge.md`](docs/bridge.md) — it maps what
transfers and what doesn't.

---

## The five tools

| Tool | Role | What it does |
|------|------|-------------|
| **[camazotz](https://github.com/babywyrm/camazotz)** | Vulnerable target | Intentionally vulnerable MCP server — 52 labs across five identity lanes and five transport surfaces (A–E), covering the OWASP MCP Top 10 |
| **[nullfield](https://github.com/babywyrm/nullfield)** | Policy arbiter | Sidecar that intercepts every `tools/call` and enforces ALLOW / DENY / HOLD / SCOPE / BUDGET before forwarding |
| **[mcpnuke](https://github.com/babywyrm/mcpnuke)** | Scanner | Outside-in MCP scanner — static, behavioral, and AI-assisted probes; emits findings **and** a nullfield policy |
| **[stoneburner](https://github.com/babywyrm/stoneburner)** | LLM eval | Provider benchmarking plus adversarial / red-blue resilience eval, security-architecture review (`archreview`), and live infrastructure probing with multi-judge consensus |
| **[skillseraph](https://github.com/babywyrm/skillseraph)** | Config scanner | Static analyzer for the control plane — scans `AGENTS.md`, `SKILL.md`, rules, hooks, and MCP configs across 11 platforms for poisoning and supply-chain tampering |

Each ships independently. They are stronger together.

---

## The four lenses

The ecosystem is described through four complementary views. Skim these first —
they are the map that keeps everything else in context.

| Lens | Question it answers | Start |
|------|---------------------|-------|
| **Surface** | What artifacts exist in an agentic workspace, and how do I vet each? | [`docs/taxonomy/surfaces.md`](docs/taxonomy/surfaces.md) |
| **Attack** | What can go wrong? | [`docs/attack-path-atlas.md`](docs/attack-path-atlas.md) — 61 paths, domains A–K |
| **Identity** | Who is calling, over what transport? | [`docs/identity-flows.md`](docs/identity-flows.md) · [`docs/taxonomy/lanes.yaml`](docs/taxonomy/lanes.yaml) |
| **Tool** | What finds / enforces / measures each? | [`docs/ecosystem.md`](docs/ecosystem.md) · [`docs/reference/`](docs/reference/) |

Index and cross-reference contract: [`docs/taxonomy/`](docs/taxonomy/README.md).

---

## The feedback loop

Scan → Recommend → Enforce → Validate — one script, one cycle:

```bash
# Local — generates policy, does not apply
./scripts/feedback-loop.sh http://localhost:8080/mcp

# Kubernetes — applies as a NullfieldPolicy CRD, hot-reloads the sidecar
./scripts/feedback-loop.sh http://<NODE_IP>:30080/mcp --k8s camazotz

# With Claude analysis
ANTHROPIC_API_KEY=... ./scripts/feedback-loop.sh http://localhost:8080/mcp --claude
```

Detail: [`docs/feedback-loop.md`](docs/feedback-loop.md).

---

## Quick start

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

Kubernetes, Helm, and Teleport options: [`docs/deployment-guide.md`](docs/deployment-guide.md).

---

## Start here, by goal

| I want to… | Go |
|------------|----|
| Understand how MCP security differs from API security | [`docs/bridge.md`](docs/bridge.md) |
| Understand every surface and how to vet it | [`docs/taxonomy/surfaces.md`](docs/taxonomy/surfaces.md) |
| See the whole threat model | [`docs/attack-path-atlas.md`](docs/attack-path-atlas.md) |
| Attack a vulnerable server | [Walkthrough 1 — The Attack](docs/walkthroughs/attack.md) |
| Defend with runtime policy | [Walkthrough 2 — The Defense](docs/walkthroughs/defense.md) |
| Run the full scan → enforce → validate loop | [Walkthrough 5 — Live Loop](docs/walkthroughs/live-loop.md) |
| Scan agent config files before an agent reads them | [`docs/reference/skillseraph.md`](docs/reference/skillseraph.md) |
| Run a full deployment scenario (bot, CI/CD, code review, SaaS) | [`docs/campaigns/`](docs/campaigns/README.md) |
| Stand up a zero-trust control plane (runnable) | [`blueprints/zero-trust-control-plane/`](blueprints/zero-trust-control-plane/README.md) |
| Follow a structured curriculum | [`docs/learning-path.md`](docs/learning-path.md) |
| See what's mature, thin, and planned next | [`docs/roadmap.md`](docs/roadmap.md) |

---

## Who this is for

- **Security engineers** protecting MCP in production Kubernetes → [Golden Path](docs/golden-path.md)
- **Red team** testing MCP defenses → [Walkthrough 1](docs/walkthroughs/attack.md)
- **Blue team** authoring runtime policy → [Walkthrough 2](docs/walkthroughs/defense.md)
- **Config / supply-chain defenders** hardening the agent control plane → [skillseraph](docs/reference/skillseraph.md)
- **Platform engineers** building agentic infrastructure → [Deployment Guide](docs/deployment-guide.md)

---

## Walkthroughs

Twelve hands-on labs live in [`docs/walkthroughs/`](docs/walkthroughs/). The core
path is **1 → 2 → 5**:

- **1. The Attack** — scan camazotz with mcpnuke, map attack chains
- **2. The Defense** — generate a nullfield policy, apply it, re-scan to confirm
- **5. Live Feedback Loop** — the full cycle in one script

The rest go deeper: delegation-chain identity dilution, attacks beyond MCP
(LangChain / CLI agents), AI-governance-gate bypass, token cross-pollution, and
guardrail-resistance testing.

---

## Reference & deployment

- Tool references: [`docs/reference/`](docs/reference/) — camazotz · nullfield · mcpnuke · stoneburner · skillseraph
- Architecture: [`docs/ecosystem.md`](docs/ecosystem.md) · [`docs/golden-path.md`](docs/golden-path.md)
- Deployment: [`docs/deployment-guide.md`](docs/deployment-guide.md) · [`docs/teleport/setup.md`](docs/teleport/setup.md)
- Roadmap: [`docs/roadmap.md`](docs/roadmap.md)
- Contributing: [`CONTRIBUTING.md`](CONTRIBUTING.md)

---

## License

MIT. Each sibling project is independently MIT-licensed.
[camazotz](https://github.com/babywyrm/camazotz/blob/main/LICENSE) ·
[nullfield](https://github.com/babywyrm/nullfield/blob/main/LICENSE) ·
[mcpnuke](https://github.com/babywyrm/mcpnuke/blob/main/LICENSE) ·
[stoneburner](https://github.com/babywyrm/stoneburner/blob/main/LICENSE) ·
[skillseraph](https://github.com/babywyrm/skillseraph/blob/main/LICENSE) ·
[agentic-sec](./LICENSE)
