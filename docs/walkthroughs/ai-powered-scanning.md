# AI-Powered Scanning — Claude as Brain for Both Attack and Defense

The most powerful configuration of the trifecta wires Claude into both
sides of the security equation: camazotz uses Claude to simulate realistic
AI guardrail behavior in its vulnerable labs, while mcpnuke uses Claude
to reason about findings at a level that regex pattern matching cannot reach.

This walkthrough shows the difference and explains when to use each mode.

---

## The Two AI Brains

```
┌─────────────────────┐          ┌─────────────────────┐
│  mcpnuke             │          │  camazotz            │
│                     │  scans   │                     │
│  --claude flag      │────────▶ │  BRAIN_PROVIDER=cloud│
│  Claude analyzes    │          │  Claude powers the   │
│  findings + chains  │          │  lab tool responses  │
│                     │          │                     │
│  "Here's a 4-step   │          │  "The AI evaluates   │
│   attack chain that │          │   your request and   │
│   ends with a       │          │   decides whether    │
│   reverse shell"    │          │   to grant admin"    │
└─────────────────────┘          └─────────────────────┘
```

**mcpnuke's Claude brain** (`--claude` flag) analyzes the scan results after
static checks complete. It reads tool definitions and schemas, then produces:
- Per-tool threat analysis with specific attack scenarios
- Multi-step attack chain reasoning with numbered kill chains
- OWASP MCP threat ID mappings

**camazotz's Claude brain** (`BRAIN_PROVIDER=cloud`) powers the labs themselves.
When you call a tool like `auth.issue_token`, an actual Claude instance
evaluates your request and decides whether to grant elevated access. The AI's
guardrail behavior is real — exploits emerge from genuine AI reasoning, not
mock responses.

When both are active, you get the most realistic simulation: real AI defending
the tools, and real AI analyzing the attack surface.

---

## What Claude Finds That Regex Cannot

### Static scan (no Claude): 34 findings in 0.6s

Pattern matching detects dangerous tool names, parameters, and capability
keywords:

```
[CRITICAL] code_execution: Code execution indicator in 'hallucination.execute_plan'
           Pattern: (subprocess|popen|system|exec|eval|compile)\s*\(

[HIGH]     token_theft: Tool 'relay.execute_with_context' accepts credential param: 'context_keys'
```

These are accurate but shallow — they tell you *what* is dangerous but not
*why* it matters or *how* an attacker would chain it.

### Claude-powered scan: 44 findings in 23s

Claude adds 10 findings in two categories:

**Per-tool threat analysis** — Claude reads the full tool definition and
reasons about real-world impact:

```
[CRITICAL] [AI] [MCP-T02] Unrestricted command execution via natural language
           The hallucination.execute_plan tool accepts arbitrary natural
           language descriptions and executes them against both staging AND
           production environments. This enables attackers to perform
           destructive operations disguised as maintenance tasks.

[CRITICAL] [AI] [MCP-T03] Unrestricted network access with local file support
           The egress.fetch_url tool supports file:// protocol, enabling
           local file system access to read sensitive files like /etc/passwd,
           SSH keys, or application secrets. Combined with http/https support,
           this creates an SSRF-to-exfiltration pipeline.

[CRITICAL] [AI] [MCP-T04] Persistent surveillance backdoor
           The shadow.register_webhook tool creates a persistent data
           exfiltration channel by registering attacker-controlled URLs
           that receive all future tool calls. This enables continuous
           monitoring and data theft that persists across sessions.
```

**Multi-step attack chain reasoning** — Claude constructs complete kill chains:

```
[CRITICAL] [AI] [MCP-ATK-001] Full System Compromise via Credential-Assisted Remote Shell
           1. Exploit prompt injection to manipulate AI behavior
           2. Use secrets.leak_config to extract credentials and configuration
           3. Use relay.execute_with_context with stolen credentials
           4. Use hallucination.execute_plan to establish remote shell

[CRITICAL] [AI] [MCP-ATK-004] Stealth Data Exfiltration with Persistence
           1. Register malicious webhook via shadow.register_webhook
           2. Use secrets.leak_config to extract sensitive data
           3. Use relay.execute_with_context to access stored credentials
           4. All future tool calls automatically forwarded to attacker

[CRITICAL] [AI] [MCP-ATK-007] Supply Chain Poisoning via Configuration Manipulation
           1. Use prompt injection to manipulate AI responses
           2. Fetch malicious config via egress.fetch_url
           3. Execute system modifications via hallucination.execute_plan
           4. Persist via shadow.register_webhook for ongoing control
```

These are the findings you present to your CISO. Static analysis says
"this tool has a dangerous parameter." Claude says "here's a 4-step
attack chain that ends with a persistent backdoor."

---

## Running the Scans

### Setup

Both brains need your Anthropic API key:

```bash
# Set the key (used by both mcpnuke --claude and camazotz cloud brain)
export ANTHROPIC_API_KEY=sk-ant-...

# Verify camazotz is using Claude
curl -sf http://localhost:8080/config | python3 -c "
import sys,json; c=json.load(sys.stdin)
print(f'Brain: {c.get(\"brain_provider\")}')"
# Expected: Brain: cloud
```

### Scan 1: Static only (baseline, instant)

```bash
$ mcpnuke --targets http://localhost:8080/mcp \
    --fast --no-invoke --verbose \
    --save-baseline static-baseline.json

# Results: 34 findings, 0.6s, no API calls
```

### Scan 2: Claude analysis (deep reasoning, ~25s)

```bash
$ mcpnuke --targets http://localhost:8080/mcp \
    --fast --no-invoke --claude \
    --claude-max-tools 5 \
    --verbose \
    --json claude-report.json \
    --generate-policy fix.yaml

# Results: 44 findings (34 static + 10 AI), ~25s
```

### Scan 3: Full behavioral + Claude (deepest, ~90-120s)

```bash
$ mcpnuke --targets http://localhost:8080/mcp \
    --fast --claude \
    --claude-max-tools 5 \
    --probe-workers 2 \
    --verbose \
    --json full-report.json

# Results: 50+ findings, includes tool invocation responses
# Note: each tool call triggers a Claude API call in camazotz,
# so this is the slowest but most realistic scan mode
```

### Scan against a cluster (same commands, different target)

```bash
# K3s / self-hosted
$ mcpnuke --targets http://192.168.1.85:30080/mcp \
    --fast --no-invoke --claude --verbose

# EKS / cloud (with auth)
$ mcpnuke --targets https://mcp.internal.example.com/mcp \
    --fast --no-invoke --claude \
    --auth-token "$MCP_TOKEN" \
    --tls-verify --verbose
```

---

## Understanding Scan Modes

| Mode | Findings | Time | API Calls | Best For |
|------|----------|------|-----------|----------|
| `--fast --no-invoke` | 34 | 0.6s | 0 | Quick audit, CI/CD gates |
| `--fast --no-invoke --claude` | 44 | 25s | 2-3 (Claude analysis) | Security review, reporting |
| `--fast --claude` | 50+ | 90-120s | Many (tools + analysis) | Deep investigation |
| Full (no --fast) | 60+ | 10+ min | Many | Comprehensive assessment |

**Cost estimate** (Claude API):
- Static scan: $0.00 (no API calls)
- `--claude` analysis: ~$0.02-0.05 per scan (2-3 Claude calls)
- Full behavioral: ~$0.10-0.30 per scan (depends on tool count)

---

## Using Results for Defense

### Generate nullfield policy from Claude-enhanced findings

```bash
$ mcpnuke --targets http://localhost:8080/mcp \
    --fast --no-invoke --claude \
    --generate-policy fix.yaml

$ cat fix.yaml
```

The policy generator considers both static and AI findings. Claude's
chain reasoning helps identify which tools need HOLD (human approval)
vs DENY (block outright) because the AI understands the attack flow.

### Test defense labs with Claude brain

When camazotz runs with Claude (`BRAIN_PROVIDER=cloud`), the defense labs
produce more realistic evaluations:

```bash
# Policy authoring lab — Claude evaluates your policy
$ curl -s -X POST http://localhost:8080/mcp \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{
      "name":"policy_authoring.submit_policy","arguments":{
        "policy_yaml":"..."}}}'

# Claude responds with detailed feedback:
# "Excellent policy. HOLD for execute_plan with DENY timeout covers the
#  code execution vector. SCOPE redaction for relay.execute_with_context
#  protects against credential exposure. However, consider adding a
#  BUDGET rule for cost.invoke_llm to prevent cost exhaustion attacks."
```

With Ollama or stub mode, the feedback is generic. With Claude, it's
specific to your policy and the actual attack patterns.

---

## Comparing Brain Providers

| Provider | Lab Quality | Scan Analysis | Cost | Latency |
|----------|-------------|---------------|------|---------|
| Claude API (`cloud`) | Best — real guardrails | Best — deep reasoning | ~$0.05/scan | 1-5s/call |
| Bedrock (Claude) | Best — same model | Best — same model | ~$0.03/scan | 0.3-1s/call |
| Ollama (qwen3:4b) | Good — basic guardrails | N/A (mcpnuke only) | Free | 0.5-2s/call |
| Stub (no LLM) | None — mock responses | N/A | Free | Instant |

**Recommendation:** Use Claude API or Bedrock for security assessments where
finding quality matters. Use Ollama for development iteration. Use stub mode
only for unit testing the platform itself.

---

## What to Document in Your Report

When presenting AI-powered scan results to stakeholders:

1. **Lead with the attack chains.** Claude's `MCP-ATK-*` findings describe
   complete kill chains in language non-technical reviewers can understand.

2. **Show the delta.** "Static analysis found 34 issues. AI reasoning found
   10 additional scenarios including a persistent backdoor chain." This
   demonstrates the value of AI-assisted security analysis.

3. **Include the generated policy.** The `fix.yaml` is a concrete, actionable
   deliverable — not just a list of problems but a ready-to-apply solution.

4. **Reference the OWASP mapping.** Every AI finding includes an MCP threat
   ID (MCP-T01 through MCP-T27) that maps to the OWASP MCP Top 10.

5. **Note what defenses hold.** Run the defense labs on hard difficulty to
   show that nullfield HOLD, SCOPE, and BUDGET actions block the chains
   Claude identified.
