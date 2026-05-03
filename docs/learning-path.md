# Learning Path

Three structured tracks for security practitioners new to MCP and agentic AI
security. Each track builds on [`docs/bridge.md`](bridge.md) — read that first.

**Prerequisites for all tracks:** Familiarity with offensive or defensive
security fundamentals (OWASP Top 10, JWT, basic network security). Docker
installed. Python 3.11+. No MCP experience required.

---

## Track 1 — Red Team (~4 hours)

*For offensive practitioners who want to enumerate and exploit MCP attack surfaces.*

**You will be able to when done:**
- Enumerate any MCP server's tool catalog and map it to the OWASP MCP Top 10
- Execute prompt injection, SSRF, confused-deputy, and delegation-chain attacks
- Run mcpnuke against a live target and interpret the findings report
- Identify which identity lane a target deployment uses and what that implies for the attack surface

| Step | Resource | Time |
|------|----------|------|
| 1 | [`docs/bridge.md`](bridge.md) — mental model foundation | 15 min |
| 2 | [Walkthrough 1 — The Attack](walkthroughs/attack.md) — scan camazotz with mcpnuke | 30 min |
| 3 | [Walkthrough 4 — AI-Powered Scanning](walkthroughs/ai-powered-scanning.md) — Claude reasoning over findings | 45 min |
| 4 | [Walkthrough 6 — Delegation Chains](walkthroughs/delegation-chains.md) — multi-agent identity dilution | 45 min |
| 5 | [Walkthrough 8 — Beyond MCP](walkthroughs/beyond-mcp.md) — same attacks across LangChain, OpenAI, CLI agents | 30 min |
| 6 | camazotz labs at **hard** difficulty — all 37 labs, any order | 90 min |

---

## Track 2 — Blue Team (~3 hours)

*For defenders and policy authors who want to write and validate nullfield policy.*

**You will be able to when done:**
- Write a NullfieldPolicy CRD from a mcpnuke findings report
- Apply DENY, HOLD, SCOPE, BUDGET, and ALLOW rules with appropriate targeting
- Threat-model any agentic deployment using the 5-lane × 5-transport framework
- Present a production security architecture to a security review board

| Step | Resource | Time |
|------|----------|------|
| 1 | [`docs/bridge.md`](bridge.md) — mental model foundation | 15 min |
| 2 | [Walkthrough 2 — The Defense](walkthroughs/defense.md) — generate + apply nullfield policy | 45 min |
| 3 | [Walkthrough 3 — Lab Practice](walkthroughs/practice.md) — write policy manually, get scored | 60 min |
| 4 | [nullfield Quick Reference](reference/nullfield.md) — all five actions, policy YAML syntax | 20 min |
| 5 | [`docs/golden-path.md`](golden-path.md) — production security architecture | 40 min |

---

## Track 3 — Full Loop (~3 hours)

*For platform engineers and security engineers who want to run the complete
scan → enforce → validate cycle in their own environment.*

**You will be able to when done:**
- Run the feedback loop against any MCP target in any environment (Docker Compose, k3s, EKS)
- Use `scripts/feedback_loop.py` with `--scanner`, `--apply-backend`, and `--ssh-host` targeting
- Interpret the delta between a bypass-path scan and a policed-path scan
- Set up the full stack (camazotz + nullfield + mcpnuke) in a Kubernetes cluster

| Step | Resource | Time |
|------|----------|------|
| 1 | [`docs/bridge.md`](bridge.md) — mental model foundation | 15 min |
| 2 | [Walkthrough 7 — Flow Types in Practice](walkthroughs/flow-types-in-practice.md) — live captures across all 5 lanes | 60 min |
| 3 | [Walkthrough 5 — Live Feedback Loop](walkthroughs/live-loop.md) — automated cycle in one script | 20 min |
| 4 | [`docs/feedback-loop.md`](feedback-loop.md) — full Python orchestrator reference | 20 min |
| 5 | [`docs/deployment-guide.md`](deployment-guide.md) — Docker Compose, Kubernetes, Helm, cloud | 45 min |

---

## All Three Tracks Together (~8 hours)

If you want the full picture — red + blue + loop — do them in order: Red Team
gives you the attacker's perspective, Blue Team gives you the defender's
perspective, Full Loop gives you the operator's perspective. Together they
cover every role in the feedback loop.
