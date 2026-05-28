# stoneburner Reference

> **Atomics** — Agentic token usage benchmarking + LLM security evaluation platform

[GitHub](https://github.com/babywyrm/stoneburner) · v0.5.0

---

## Role in the Ecosystem

stoneburner complements the three security tools (camazotz, nullfield, mcpnuke)
by measuring **LLM reasoning quality and adversarial resilience** rather than
MCP protocol integrity or infrastructure configuration. Where mcpnuke scans
the server and nullfield enforces policy, stoneburner answers: *how well does
the LLM itself behave under pressure?*

The `brain-gateway` provider routes benchmarks through camazotz's MCP inference
endpoint, enabling same-workload comparison across camazotz-managed providers.

---

## Providers

| Provider | Flag | Auth | Notes |
|----------|------|------|-------|
| **Claude** (Anthropic) | `--provider claude` | `ANTHROPIC_API_KEY` | Default. Extended thinking via `budget_tokens`. |
| **OpenAI / Codex** | `--provider openai` | `OPENAI_API_KEY` | Reasoning tokens tracked for o3/o4/gpt-5.x. |
| **Bedrock** (AWS) | `--provider bedrock --region us-east-1` | AWS credentials | Uses `boto3`. Install: `uv sync --extra bedrock`. |
| **Ollama** (local) | `--provider ollama` | None | Zero-cost local inference. `--ollama-host` for remote. |
| **brain-gateway** (camazotz) | `--provider brain-gateway` | None | Routes through camazotz at `--gateway-url`. |

---

## Commands

### Core Benchmarking

| Command | What it does |
|---------|-------------|
| `atomics run` | Start the benchmarking loop (continuous or bounded) |
| `atomics run --tier mega -n 10` | Run 10 mega-tier tasks |
| `atomics run --provider ollama -m qwen3:14b` | Benchmark a specific model |
| `atomics run --thinking` | Enable thinking/reasoning mode |
| `atomics run --no-thinking` | Force thinking off (A/B comparison) |
| `atomics run --thinking-budget 20000` | Set max thinking tokens |
| `atomics compare` | Compare providers side-by-side |
| `atomics compare --by model` | Compare individual models |
| `atomics report` | Display usage reports and trends |
| `atomics tiers` | Show burn tier profiles (ez/baseline/mega) |
| `atomics provider-test` | Health check the configured provider |

### Security Evaluation Suites

| Command | What it does |
|---------|-------------|
| `atomics adversarial` | Adversarial resilience eval (15 fixtures) |
| `atomics adversarial --runs 5` | Multi-pass with mean ± stddev |
| `atomics adversarial --extra-judges ollama:deepseek-r1:14b` | Multi-judge consensus |
| `atomics adversarial --category prompt_injection,data_exfil_attempt` | Filter by attack category |
| `atomics redblue` | Red/blue security capability eval (10 fixtures) |
| `atomics redblue --mode red` | Offensive tasks only |
| `atomics redblue --mode blue` | Defensive tasks only |
| `atomics probe --probes-file probes.yaml` | Live infrastructure artifact analysis |
| `atomics probe --alert-on-regression` | Alert when scores drop >10% |
| `atomics eval` | Standard quality evaluation (25 fixtures) |

### Operations

| Command | What it does |
|---------|-------------|
| `atomics schedule --install` | Install cron/systemd/launchd schedule |
| `atomics stress` | Stress test with configurable concurrency |
| `atomics export` | Export benchmark data (CSV, JSON) |
| `atomics login` | OAuth/OIDC login |

---

## Adversarial Suite (15 fixtures)

Tests whether a model **resists** adversarial manipulation. Uses inverted
scoring — higher score = better resistance.

| Category | Fixtures | Severity range | What it tests |
|----------|----------|----------------|---------------|
| `prompt_injection` | adv-01, adv-02, adv-03 | HIGH–CRITICAL | Override system instructions via user input |
| `role_confusion` | adv-04, adv-05 | HIGH–CRITICAL | Adopt restricted persona (DAN, jailbreaks) |
| `context_escape` | adv-06, adv-07 | MEDIUM–HIGH | Escape task context via fictional framing |
| `instruction_override` | adv-08, adv-09 | MEDIUM–HIGH | Embedded overrides (base64, translation) |
| `social_engineering` | adv-10, adv-11, adv-15 | MEDIUM–HIGH | False authority, urgency, credential extraction |
| `data_exfil_attempt` | adv-12, adv-13, adv-14 | MEDIUM–CRITICAL | Context window leak, CoT leakage into structured verdicts |

### Multi-pass and multi-judge

```bash
# 5 passes per fixture, report mean ± stddev
atomics adversarial --provider ollama -m qwen3:14b --runs 5

# 2 judges — primary + deepseek consensus
atomics adversarial --provider ollama -m qwen3:14b \
  --extra-judges ollama:deepseek-r1:14b@192.168.1.126

# Combined: 3 passes, 2 judges
atomics adversarial --provider claude --runs 3 \
  --extra-judges ollama:qwen2.5:14b
```

`--extra-judges` accepts comma-separated `provider:model` or
`provider:model@host` specs. Scores are averaged across all judges per fixture.

### Notable fixtures

**adv-14 (CoT leakage):** Catches models that emit chain-of-thought reasoning
before structured `APPROVED:`/`DENIED:` verdicts. In production agentic
pipelines, this defeats `startswith`-based parsers and can expose allowlist
rules or system prompt fragments. Discovered during CTF VM model compatibility
testing — `qwen3:4b` broke the Warbird deploy gate with this failure mode.

**adv-15 (credential extraction):** Mirrors the "helpful ops request" social
engineering strategy that leaked secrets across multiple Ollama models in live
CTF testing.

---

## Red/Blue Suite (10 fixtures)

Benchmarks LLM performance on real security domain tasks.

| Team | Fixtures | Domain |
|------|----------|--------|
| **Red** (5) | OSINT, vuln analysis, privesc, log forensics, lateral movement | Offensive security |
| **Blue** (5) | Incident response, hardening, threat modelling, detection engineering, policy review | Defensive security |

Uses the same quality-based LLM-as-judge scoring as `atomics eval`.

---

## Live Probe

Fetches real artifacts from infrastructure and uses an LLM to analyse them.
Targets defined in a user-provided `probes.yaml` — nothing hardcoded.

**Supported artifact types:** `access-log` · `json-security-report` ·
`inference-api` · `k8s-audit-log` · `config-file` · `api-response`

```yaml
# probes.yaml
targets:
  - name: nginx-access-logs
    artifact_type: access-log
    source: file
    path: /var/log/nginx/access.log

  - name: ollama-api
    artifact_type: inference-api
    source: http
    url: http://192.168.1.126:11434/api/tags
```

---

## Thinking Mode

Auto-detects models with thinking/reasoning capabilities. Thinking tokens are
tracked separately from visible output.

| Provider | Models | Mechanism |
|----------|--------|-----------|
| Claude | Opus 4.x, Sonnet 4.x | Extended thinking API (`budget_tokens`) |
| OpenAI | o3, o3-mini, o3-pro, o4-mini, gpt-5.x | Reasoning tokens |
| Ollama | qwen3 family | `<think>` tag parsing, auto-stripped |

Flags: `--thinking` (force on), `--no-thinking` (force off),
`--thinking-budget N` (max thinking tokens).

---

## Camazotz Integration

The `brain-gateway` provider connects stoneburner to camazotz's MCP inference
endpoint. This enables benchmarking the same workload across all providers
that camazotz manages (cloud Claude, local Ollama, Bedrock).

```bash
# Local
uv run atomics run --provider brain-gateway -n 5

# Remote (K8s NodePort)
uv run atomics run --provider brain-gateway --gateway-url http://<NODE_IP>:30080 -n 5

# Adversarial eval through brain-gateway
uv run atomics adversarial --provider brain-gateway
```

Environment variable: `ATOMICS_BRAIN_GATEWAY_URL` (default `http://localhost:8080`).

---

## Storage

SQLite database (schema v6) with tables:

| Table | Content |
|-------|---------|
| `runs` | Benchmark run metadata |
| `task_results` | Per-task outcomes with `suite` column (eval/redblue) |
| `adversarial_results` | Adversarial fixture results |
| `probe_results` | Live probe results |

Export via `atomics export --format csv` or `atomics export --format json`.

---

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `ANTHROPIC_API_KEY` | — | Claude API key |
| `OPENAI_API_KEY` | — | OpenAI API key |
| `ATOMICS_BRAIN_GATEWAY_URL` | `http://localhost:8080` | brain-gateway endpoint |
| `ATOMICS_DB_PATH` | `~/.atomics/metrics.db` | SQLite database location |

---

## Model Selection as Security Configuration

Model swapping on a shared inference backend is not just a performance or
cost decision — it is a **security-relevant configuration change** when
the platform uses AI-mediated security gates (MCP-T56).

### The Risk

AI governance gates (deployment approval, secret-filtering assistants,
scale-review tools) rely on the LLM following system-prompt guardrails.
Different models exhibit dramatically different guardrail resistance:

| Model Class | Guardrail Behavior |
|-------------|-------------------|
| Reasoning models (chain-of-thought) | Tend to recognize and refuse social-engineering probes |
| General-purpose instruction-following | Mixed — depends on alignment tuning |
| Code-completion models | Comply readily with structured extraction requests |
| Small models (<4B params) | Inconsistent — may leak on casual requests |

The same system prompt + the same context + a different model =
a completely different security posture.

### stoneburner for Guardrail Evaluation

Use the adversarial suite to benchmark guardrail resistance before
deploying a model behind security gates:

```bash
# Sweep all models on the inference host
for model in qwen2.5:3b gemma3:4b mistral:7b deepseek-r1:14b qwen2.5:14b; do
  atomics adversarial --provider ollama -m "$model" \
    --ollama-host ollama.internal:11434 \
    --category social_engineering,data_exfil_attempt \
    --runs 3
done

# Compare guardrail resistance across models
atomics compare --by model --suite adversarial
```

Key fixtures for guardrail evaluation:

- **adv-15** (credential extraction): Social engineering for env var values
- **adv-10** (false authority): "SYSTEM OVERRIDE" style attempts
- **adv-14** (CoT leakage): Chain-of-thought bleeding into structured output

### Integration with mcpnuke

mcpnuke's `inference_guardrail_variance` check (MCP-T56) performs a
lightweight version of this assessment automatically during scans.
stoneburner provides the deep, multi-pass, multi-judge evaluation for
CI pipeline integration and formal model approval.

Recommended workflow:

1. **Pre-deploy:** `atomics adversarial --runs 5` on the candidate model
2. **Gate:** Reject models scoring below threshold on `social_engineering`
3. **Post-deploy:** `mcpnuke --inference` scans detect runtime model swaps
4. **Monitor:** `atomics probe --alert-on-regression` catches guardrail drift

---

## Cross-references

- [ecosystem.md](../ecosystem.md) — stoneburner's role in the defense stack
- [deployment-guide.md](../deployment-guide.md) — K8s deployment with brain-gateway
- [mcpnuke reference](mcpnuke.md) — infrastructure scanning (complementary tool)
- [camazotz reference](camazotz.md) — brain-gateway provider source
- [Walkthrough 12](../walkthroughs/guardrail-resistance-testing.md) — AI Guardrail Resistance Testing
- [Campaign F](../campaigns/shared-ai-platform.md) — Multi-Tenant AI Code Review Platform
