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

### Static scan (no Claude): 179 findings in 0.7s

Pattern matching detects dangerous tool names, parameters, and capability
keywords across all 99 tools:

```
[CRITICAL] code_execution: Code execution indicator in 'hallucination.execute_plan'
           Pattern: (subprocess|popen|system|exec|eval|compile)\s*\(

[HIGH]     token_theft: Tool 'relay.execute_with_context' accepts credential param: 'context_keys'
```

These are accurate but shallow — they tell you *what* is dangerous but not
*why* it matters or *how* an attacker would chain it.

### Claude-powered scan: 96 findings in 184s (top 15 tools, all 3 phases)

Claude operates in three phases:

**Phase 1 — Schema analysis** (10 findings): Claude reads each tool's full
definition and reasons about real-world impact:

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

**Phase 2 — Live tool invocation** (10 findings): Claude generates
semantically adversarial arguments (Tier 2), calls each tool, then analyzes
the responses. This surface is completely invisible to static analysis:

```
[CRITICAL] Credential leak in tool 'secrets.leak_config' response: aws_access_key
[CRITICAL] Live exfil confirmed: 'secrets.leak_config' → 'shadow.register_webhook'
[CRITICAL] Credential exposed in resource 'tenant://memories/alice': api_key
```

**Phase 3 — Chain reasoning** (5 insights): Claude reasons across all findings
to construct complete kill chains:

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

### The coverage knob

`--coverage N` is the dial between speed and depth. Pick the level that fits
your time budget:

| Command | Tools sampled | Time | Best for |
|---------|--------------|------|----------|
| `--no-invoke --coverage 0` | all 99 | ~1s | Static baseline, CI gate |
| `--coverage 5` (`--fast`) | top 5 | ~2 min | Quick PR review |
| `--coverage 15 --claude` | top 15 | ~3 min | Sprint security review |
| `--coverage 0 --claude` | all 99 | ~30+ min | Full assessment |

### Scan 1: Static baseline (all tools, instant)

```bash
mcpnuke --targets http://localhost:8080/mcp \
  --no-invoke --coverage 0 --verbose \
  --profile profiles/camazotz.json \
  --json baseline.json

# Results: 179 findings across 99 tools, 0.7s, zero API calls
```

### Scan 2: Claude analysis (top 15 tools, ~3 min)

```bash
mcpnuke --targets http://localhost:8080/mcp \
  --coverage 15 --claude \
  --claude-model claude-sonnet-4-20250514 \
  --profile profiles/camazotz.json \
  --diff-baseline baseline.json \
  --verbose \
  --json claude-report.json

# Results: 96 findings (15 tools scanned), ~184s
# Phase 1: 10 AI schema findings
# Phase 2: 10 live invocation findings
# Phase 3: 5 chain reasoning insights
```

### Reading the diff output

When `--diff-baseline` is set, the terminal shows (and `claude-report.json`
includes) a diff block:

```
── Diff vs baseline ──
NEW (47):
  + [CRITICAL] Live exfil confirmed: 'secrets.leak_config' → 'shadow.register_webhook'
  + [CRITICAL] Credential exposed in resource 'tenant://memories/alice': api_key
  + [CRITICAL] Credential leak in tool 'secrets.leak_config' response: aws_access_key
  + [MEDIUM]   SSRF surface: tool 'egress.fetch_url' accepts URL params and fetches content
  + [CRITICAL] Attack chain: response_credentials → token_theft (auth.issue_token, ...)
  ... 42 more

46 unchanged finding(s) carried over.
```

The **NEW** findings are what Claude's behavioral probes discovered that
regex could not. The **unchanged** findings are where both methods agree —
those are your highest-confidence signals.

### Scan 3: Standalone diff (any two JSON files)

```bash
# Compare any two saved reports — no live target needed
mcpnuke diff baseline.json claude-report.json
```

Exit code is 1 when new findings exist — use this in CI pipelines.

### Scan against a cluster (same commands, different target)

```bash
# K3s / self-hosted NUC
mcpnuke --targets http://192.168.1.85:30080/mcp \
  --coverage 15 --claude \
  --claude-model claude-sonnet-4-20250514 \
  --profile profiles/camazotz.json \
  --diff-baseline baseline.json \
  --json cluster-report.json --verbose

# EKS / cloud (with auth)
mcpnuke --targets https://mcp.internal.example.com/mcp \
  --coverage 15 --claude \
  --auth-token "$MCP_TOKEN" \
  --tls-verify --verbose
```

---

## Understanding Scan Modes

| Mode | Tools | Findings | Time | API Calls | Best For |
|------|-------|----------|------|-----------|----------|
| `--no-invoke --coverage 0` | all 99 | 179 | ~1s | 0 | CI baseline, instant audit |
| `--fast` (= `--coverage 5`) | top 5 | ~40 | ~2 min | 0 | Quick PR check |
| `--coverage 15 --claude` | top 15 | ~96 | ~3 min | Many | Sprint review, reporting |
| `--coverage 0 --claude` | all 99 | 200+ | ~30+ min | Many | Full assessment |

Numbers above reflect a full camazotz deployment (99 tools). Results scale with server size.

**Cost estimate** (Claude API, `claude-sonnet-4-20250514`):
- Static scan: $0.00 (no API calls)
- `--coverage 15 --claude`: ~$0.05–0.10 per scan
- Full behavioral + Claude: ~$0.30–0.60 per scan (depends on tool count)

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

2. **Show the delta.** "Static analysis found 179 issues across 99 tools. AI reasoning on the top 15 tools found 47 additional scenarios including live credential exposure and a persistent exfiltration backdoor." The diff output is ready-made for this — copy the NEW block directly into your report.

3. **Include the generated policy.** The `fix.yaml` is a concrete, actionable
   deliverable — not just a list of problems but a ready-to-apply solution.

4. **Reference the OWASP mapping.** Every AI finding includes an MCP threat
   ID (MCP-T01 through MCP-T27) that maps to the OWASP MCP Top 10.

5. **Note what defenses hold.** Run the defense labs on hard difficulty to
   show that nullfield HOLD, SCOPE, and BUDGET actions block the chains
   Claude identified.
