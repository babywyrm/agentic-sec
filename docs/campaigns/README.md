# Campaigns

Campaigns are named deployment scenarios that chain multiple camazotz labs
into a single end-to-end attack → scan → defend → validate narrative.

Each campaign establishes a concrete organizational context — a customer
support bot, a CI/CD pipeline agent, a code review agent, a multi-tenant SaaS
platform — and walks through the full three-tool ecosystem:
**camazotz** (target) + **mcpnuke** (scan) + **nullfield** (enforce + validate).

---

## Available Campaigns

| Campaign | Persona | Transports | Lanes | Labs | Time |
|----------|---------|------------|-------|------|------|
| [Customer Support Bot](customer-support-bot.md) | FinTech AI support agent with access to customer records and refund tools | A | 1 | `context_lab` → `secrets_lab` → `egress_lab` → `shadow_lab` | ~60 min |
| [CI/CD Pipeline Agent](cicd-pipeline-agent.md) | Platform engineering deployment bot — merges to main trigger production deploys | B, D | 3 | `subprocess_lab` → `agent_http_bypass_lab` → `config_lab` → `attribution_lab` | ~75 min |
| [Code Review Agent](code-review-agent.md) | Cursor/Copilot-style review agent with shell execution and LangChain tools | C, D | 1→2 | `code_review_agent_lab` → `indirect_lab` → `langchain_tool_lab` → `cost_exhaustion_lab` | ~75 min |
| [Multi-Tenant SaaS AI](multi-tenant-saas.md) | B2B SaaS AI feature serving 50 enterprise customers from one deployment | C | 1, 2, 4 | `tenant_lab` → `rag_injection_lab` → `delegation_chain_lab` → `attribution_lab` | ~75 min |

---

## Campaign Format

Each campaign follows the same structure:

1. **Deployment Context** — the organization, the product, the team
2. **Architecture** — which services, which transports, which identity lanes
3. **Threat Model** — which labs map to which threats in this deployment
4. **Attack Walkthrough** — step-by-step with curl commands per lab
5. **Scanning with mcpnuke** — what the scanner finds for this scenario
6. **Defending with nullfield** — policy tailored to this deployment
7. **Validation** — re-scan confirms controls held
8. **Real-World Takeaways** — production decisions this campaign informs

---

## Prerequisites

- Camazotz running: `make up` (local) or deployed to your cluster
- mcpnuke installed: `pip install mcpnuke`
- nullfield deployed with camazotz: `make up-policed`
- Completed: [`docs/bridge.md`](../bridge.md) — mental model foundation

---

## Running a Campaign

Set difficulty for the session, then work through the campaign steps:

```bash
# Set difficulty (easy to start, hard to validate defenses)
curl -sf http://localhost:8080/config \
  -H 'Content-Type: application/json' \
  -d '{"difficulty": "easy"}'

# Then follow the campaign walkthrough steps
```

Each campaign ends with re-running the mcpnuke scan at hard difficulty and
confirming the nullfield policy causes a clean report.
