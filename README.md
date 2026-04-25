# agentic-security

Security architecture for agentic infrastructure — MCP tool execution, machine identity, and automated defense.

This is the documentation hub for three interconnected projects that form a closed-loop security stack for AI agent deployments:

| Project | Role | Repo |
|---------|------|------|
| **[camazotz](https://github.com/babywyrm/camazotz)** | Intentionally vulnerable MCP server — 31 labs covering OWASP MCP Top 10 | [github.com/babywyrm/camazotz](https://github.com/babywyrm/camazotz) |
| **[nullfield](https://github.com/babywyrm/nullfield)** | MCP arbiter proxy — ALLOW/DENY/HOLD/SCOPE/BUDGET per tool call | [github.com/babywyrm/nullfield](https://github.com/babywyrm/nullfield) |
| **[mcpnuke](https://github.com/babywyrm/mcpnuke)** | MCP security scanner — finds vulnerabilities and generates defense policy | [github.com/babywyrm/mcpnuke](https://github.com/babywyrm/mcpnuke) |

---

## The Problem

AI agents call tools. Tools have side effects. The AI cannot be trusted to make security decisions.

Every `tools/call` in an MCP deployment is a remote procedure invocation triggered by a large language model. The LLM can be manipulated by prompt injection, confused-deputy attacks, and social engineering — yet most MCP servers forward tool calls unconditionally. There is no policy layer, no identity verification, and no audit trail.

## The Solution

A closed-loop defense stack:

```
1. SCAN        mcpnuke finds vulnerabilities in the MCP server
                  ↓
2. RECOMMEND   mcpnuke --generate-policy produces nullfield YAML
                  ↓
3. ENFORCE     nullfield applies the policy, blocks attacks
                  ↓
4. VALIDATE    camazotz labs confirm the defense holds
                  ↓
               Loop back to 1 for regression testing
```

---

## Documentation

### Architecture

| Document | What it covers |
|----------|---------------|
| [The Ecosystem](docs/ecosystem.md) | How the three projects fit together — defense layers, data flows, what each solves |
| [Golden Path](docs/golden-path.md) | Production security architecture for MCP deployments — identity, registry, policy, audit |
| [The Feedback Loop](docs/feedback-loop.md) | Scan → recommend → enforce → validate — the complete operational cycle |

### Walkthroughs

| Walkthrough | What you'll do |
|------------|---------------|
| [1. The Attack](docs/walkthroughs/attack.md) | Scan camazotz with mcpnuke, understand the findings, map attack chains |
| [2. The Defense](docs/walkthroughs/defense.md) | Generate nullfield policy from findings, apply it, re-scan to prove it works |
| [3. Lab Practice](docs/walkthroughs/practice.md) | Work through defense labs — write policy, craft redaction rules, tune budgets |
| [4. AI-Powered Scanning](docs/walkthroughs/ai-powered-scanning.md) | Wire Claude into both mcpnuke and camazotz — deep reasoning, attack chain analysis, realistic AI guardrails |
| [5. Live Feedback Loop](docs/walkthroughs/live-loop.md) | Automated scan → generate → apply → validate cycle with one script |
| [6. Delegation Chain Attacks](docs/walkthroughs/delegation-chains.md) | Multi-agent identity dilution — Agent A → B → C loses human authorization |

### Deployment & Integration

| Guide | What it covers |
|-------|---------------|
| [Deployment Guide](docs/deployment-guide.md) | Local, cluster, and cloud — performance, brain providers, scan modes per environment |
| [Teleport Setup](docs/teleport/setup.md) | Machine identity for agents — tbot, K8s access, MCP App Access |
| [nullfield Quick Reference](docs/reference/nullfield.md) | The five actions, policy YAML, deployment modes, CRDs |
| [mcpnuke Quick Reference](docs/reference/mcpnuke.md) | Scan modes, Teleport checks, policy generation, baselines |
| [camazotz Quick Reference](docs/reference/camazotz.md) | Lab categories, difficulty levels, deployment options |

---

## Quick Start

### Option 1: Local (Docker Compose)

```bash
# Start the vulnerable target
git clone https://github.com/babywyrm/camazotz && cd camazotz
make env && make up

# Scan it
pip install mcpnuke
mcpnuke --targets http://localhost:8080/mcp --fast --no-invoke --verbose

# Generate a defense policy
mcpnuke --targets http://localhost:8080/mcp --fast --no-invoke --generate-policy fix.yaml
cat fix.yaml
```

### Option 2: Kubernetes (with nullfield)

```bash
# Deploy camazotz + nullfield sidecar
cd camazotz && make helm-deploy

# Deploy nullfield CRDs
kubectl apply -f https://raw.githubusercontent.com/babywyrm/nullfield/main/deploy/crds/nullfieldpolicy-crd.yaml
kubectl apply -f https://raw.githubusercontent.com/babywyrm/nullfield/main/deploy/crds/toolregistry-crd.yaml

# Scan through nullfield
mcpnuke --targets http://<NODE_IP>:30080/mcp --fast --no-invoke --generate-policy fix.yaml

# Apply the generated policy
kubectl apply -f fix.yaml
```

### Option 3: Full Stack (with Teleport)

Follow the [Teleport Setup Guide](docs/teleport/setup.md) to add machine identity for agents — short-lived certificates, K8s RBAC, MCP tool-level access control.

---

## Who This Is For

**Security engineers** evaluating how to secure MCP/agentic tool execution in production Kubernetes environments. The architecture docs and golden path are written for security review boards.

**Red team operators** testing MCP server defenses. camazotz provides 31 intentionally vulnerable labs. mcpnuke automates the attack sequences.

**Blue team defenders** learning to write nullfield policy. The defense-mode labs teach policy authoring, response redaction, and budget tuning with scored feedback.

**Platform engineers** building agentic infrastructure. The deployment guides cover Docker Compose, Kubernetes, Helm, CRDs, gateway mode, and admission webhook injection.

---

## License

Each project is independently licensed:
- camazotz: MIT
- nullfield: MIT
- mcpnuke: MIT

This documentation hub is MIT licensed.
