# stoneburner Reference

> **Atomics** — Agentic token usage benchmarking + LLM security evaluation platform

[GitHub](https://github.com/babywyrm/stoneburner) · v0.12.0 · 1715 tests · schema v20

---

## Role in the Ecosystem

stoneburner complements the three security tools (camazotz, nullfield, mcpnuke)
by measuring **LLM reasoning quality and adversarial resilience** rather than
MCP protocol integrity or infrastructure configuration. Where mcpnuke scans
the server and nullfield enforces policy, stoneburner answers: *how well does
the LLM itself behave under pressure?*

The `brain-gateway` provider routes benchmarks through camazotz's MCP inference
endpoint, enabling same-workload comparison across camazotz-managed providers.

### v0.12.0 — Distributed benchmark runs (2026-07-23)

Latest release. Schema v20, 1715 tests. Builds on the v0.11.0 surface with
split-task distributed benchmarking:

- **Distributed runs** — `atomics distributed run` submits split-mode jobs to
  the FastAPI coordinator; `atomics worker` polls the coordinator, executes tasks,
  and reports results. Workers target any provider/model/host via `--provider`,
  `--model`, `--host`. Supports mixed local-LAN and remote workers with
  per-worker API key authentication (`X-API-Key`).
- **Distributed API endpoints** — `POST /api/v1/workers/register`,
  `POST /api/v1/workers/{id}/heartbeat`, `GET /api/v1/workers/poll`,
  `POST /api/v1/distributed/runs`, `GET /api/v1/distributed/runs/{id}`, and
  `POST /api/v1/distributed/assignments/{id}/result`.
- **Coordinator resilience** — heartbeat/offline detection, assignment timeout
  requeue, retry limits, idempotent submission, and restart recovery via SQLite
  (`distributed_jobs`, `distributed_assignments`, `workers` tables).
- **Test coverage** — unit tests for coordinator edge cases (timeout, requeue,
  retry, partial failure, recovery), worker loop tests, e2e local test, and CLI
  tests for `atomics worker` and `atomics distributed`.

### v0.11.0 — API server, real RAG retrieval, richer eval surface (2026-07)

Release. Schema v20, 1683 tests. Headline additions since the v0.8.0 /
structure pass:

- **API server mode** — `atomics server` (optional `[api]` extra) exposes a
  FastAPI service with async job scheduling: `POST /api/v1/runs`,
  `POST /api/v1/evals`, `GET /api/v1/jobs/{id}`, plus comparison and recent-run
  reports. API key auth via `X-API-Key`.
- **RAG with real retrieval** — `atomics rag-index`, `atomics rag --index`, and
  `atomics rag-retrieval` (recall@k, precision@k, MRR, nDCG@k); optional
  `[rag]` extra (`sqlite-vec`, `sentence-transformers`).
- **Richer multi-turn fixtures** — 35 conversations covering contradiction
  detection, persona drift/stability, long-context retention (8+ turns),
  multi-turn tool-use chaining, and security-focused scenarios.
- **New eval suites** — `atomics codegen` (15 fixtures, functional correctness
  via execution), multilingual eval (10 fixtures / 8 languages), cost advisor
  (`atomics advisor`), webhook notifications (Slack/Discord/generic HTTP) with
  regression detection.
- **New providers** — Groq, Together AI, Google Gemini, and llama.cpp join
  Claude, OpenAI/Bedrock, Ollama, vLLM, and brain-gateway.
- **Adversarial suite expanded** — 64 → **72 fixtures**.

### v0.8.0 + structure/hardening pass (2026-07-04)

Three new adversarial suites, cross-suite plumbing, and a structural pass that
made the project contributor-ready:

- **Three new adversarial suites (64 fixtures total)** — multi-turn manipulation
  (scripted `prior_turns`), RAG/retrieved-context poisoning, and MCP
  tool-description injection (the model-reasoning analogue of the
  hammerhand/artifice tool-metadata attack surface). `ALL_FIXTURES` is now a
  single source of truth via `select_fixtures()`.
- **Cross-suite plumbing** — every suite has `Summary.to_dict()` + `--json-out`;
  `adversarial` gains `--compare` (side-by-side diff) and `--fail-on-resilience`
  (CI gate); `redblue` gains `--runs` variance; suite-isolated
  `export --suite {eval,redblue,adversarial,...}`; adversarial/probe/archreview
  now persist with parent run rows.
- **New-model research** — mistral-small:24b 78.2% vs mistral-nemo:12b 61.9% on
  the 64-fixture suite; the tool-description-injection suite was the most
  discriminating (surfaced weaknesses the 32-fixture set missed).
- **Structure & hardening** — `ARCHITECTURE.md` contributor map; deduped
  primitives (`stats.py`, single provider factory); `py.typed` + a mypy gate in
  CI; security: `secrets get` masked by default (`--show` to reveal) and a DB
  backup before any schema-migration wipe.

### Earlier maturity pass (2026-06 / v0.7.0)

- **`atomics archreview`** — security-architecture repo benchmark: deterministic
  token-budgeted evidence packs scored by objective difficulty-weighted OWASP
  recall/precision against per-repo answer keys, plus a self-judge-guarded
  reasoning score and multi-round finding-set robustness.
- **MCP/agentic + zero-trust adversarial fixtures** — tool-call compliance,
  authority fabrication, breakglass injection, context poisoning, agent-loop
  escape, tool-use safety. Model-level resistance, not live endpoint scanning.
- **Adversarial leaderboard** — `docs/LEADERBOARD.md` tracks a 20-model brainbox
  sweep with qwen2.5:7b as judge (`qwen3.5:4b` 98%, `gemma4:12b` 94%).
- **Secrets layer** — `atomics secrets` stores API keys in the OS keychain (env
  and `.env` remain first-class).
- **Distribution readiness** — CI + PyPI trusted-publishing workflows; clean
  sdist + wheel builds verified.

---

## Providers

| Provider | Flag | Auth | Notes |
|----------|------|------|-------|
| **Claude** (Anthropic) | `--provider claude` | `ANTHROPIC_API_KEY` | Default. Extended thinking via `budget_tokens`. |
| **OpenAI / Codex** | `--provider openai` | `OPENAI_API_KEY` | Reasoning tokens tracked for o3/o4/gpt-5.x. Install: `uv sync --extra openai`. |
| **Bedrock** (AWS) | `--provider bedrock --region us-east-1` | AWS credentials | Uses `boto3`. Install: `uv sync --extra bedrock`. |
| **Ollama** (local) | `--provider ollama` | None | Zero-cost local inference. `--ollama-host` for remote. |
| **vLLM / OpenAI-compatible** | `--provider vllm` | None | Speaks `/v1/chat/completions`. Targets vLLM, LiteLLM, etc. `--vllm-host` for remote. `ATOMICS_VLLM_HOST` / `ATOMICS_VLLM_MODEL`. |
| **Groq** (cloud) | `--provider groq` | `GROQ_API_KEY` | Fast cloud inference via httpx. |
| **Together AI** (cloud) | `--provider together` | `TOGETHER_API_KEY` | Cloud open-model hosting via httpx. |
| **Google Gemini** | `--provider gemini` | `GEMINI_API_KEY` | Google AI Studio / Gemini API via httpx. |
| **llama.cpp** (local) | `--provider llamacpp` | None | Direct llama-server / llama-cpp-python. `ATOMICS_LLAMACPP_HOST` (default `http://localhost:8080`). |
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
| `atomics compare --output results.json` | Write JSON comparison alongside table |
| `atomics report` | Display usage reports and trends |
| `atomics tiers` | Show burn tier profiles (ez/baseline/mega) |
| `atomics provider-test` | Health check the configured provider |
| `atomics doctor` | Check installation health and config |

### Model Discovery & Multi-Model Sweeps

| Command | What it does |
|---------|-------------|
| `atomics models` | List available models on Ollama host with class/thinking annotations |
| `atomics models --provider vllm --vllm-host URL` | List models from a vLLM/LiteLLM gateway (`GET /v1/models`) |
| `atomics sweep --all-local` | Discover and evaluate all local models |
| `atomics sweep --models qwen2.5:7b,qwen3:14b` | Evaluate specific models head-to-head |
| `atomics sweep --provider vllm --vllm-host URL --models m1,m2 --judge-provider vllm` | Sweep against vLLM/LiteLLM gateway |
| `atomics sweep --provider claude --models claude-haiku-4-5-20251001` | Sweep cloud models |
| `atomics sweep --fixtures ev-01,ev-06,ev-08` | Evaluate against specific fixtures |
| `atomics sweep --save` | Persist sweep results to database |

### Stress Testing & Capacity

| Command | What it does |
|---------|-------------|
| `atomics stress --model qwen2.5:7b` | Ramp concurrency to find GPU saturation point |
| `atomics stress --models qwen2.5:3b,qwen2.5:7b` | Multi-model VRAM contention — solo baseline then simultaneous, reports per-model TPS degradation factor |
| `atomics stress --provider openai --model gpt-4o-mini` | Stress test a cloud API endpoint |
| `atomics stress --provider claude --model claude-haiku-4-5-20251001` | Stress test Claude |
| `atomics capacity --model qwen2.5:7b --users 50` | Project user load from stress data |
| `atomics capacity --peak-tps 120 --single-latency 8000 --users 200` | Manual capacity projection |

### Stability, Regression & Mixed Workloads

| Command | What it does |
|---------|-------------|
| `atomics soak 30m --model qwen2.5:7b` | Long-duration stability test; linear-regression drift → STABLE / DEGRADED / UNSTABLE |
| `atomics soak --save-baseline NAME` | Capture key metrics (avg/peak tok/s, P95, error rate) under a named baseline |
| `atomics soak --compare-baseline NAME` | Colour-coded delta vs a saved baseline → IMPROVED / STABLE / REGRESSED |
| `atomics baselines` | List all saved baselines |
| `atomics scenario -w gate:qwen2.5:7b:4 -w eval:qwen2.5:7b:2` | Mixed-workload simulation; per-workload P50/P95, SLA, cross-workload interference |
| `atomics scenario --ramp 10` | Stagger worker start times so load builds gradually |

### QA / CTF Solvability & Gate Regression

| Command | What it does |
|---------|-------------|
| `atomics qa --fixtures qa/examples/gate.yaml` | Validate CTF solvability / AI-gate regression from a YAML fixture (pass/fail/must-match regex) |
| `atomics qa --fail-fast` | Stop at first failing fixture |
| `atomics qa --profile profiles/local/gate.yaml` | Route fixture queries through a TargetProfile (app HTTP endpoint or Ollama w/ custom system prompt) |

Custom **target profiles** (`--profile`) also apply to `soak`, `stress`, and
`scenario` — YAML defines an `ollama` (custom system prompt/temp) or `http`
(arbitrary endpoint + body template + response parsing) target. Sensitive
profiles live in gitignored `profiles/local/`.

### CTF Model Compatibility Labels

For AI-backed challenge QA, model results should be labeled by the role they
actually satisfy rather than by a vague "works" verdict:

| Label | Meaning |
|---|---|
| `UNTESTED` | No evidence for this model/backend/challenge combination yet. |
| `FUNCTION_COMPATIBLE` | Health, inference, output contracts, and individual AI-mediated tool checks pass. |
| `WALKTHROUGH_COMPATIBLE` | The full player-facing challenge chain passes over repeated rounds. |
| `TOO_SAFE_FOR_CHAIN` | The model refuses or redacts an intentionally vulnerable behavior required for challenge solvability. |
| `UNSAFE_GATE_BEHAVIOR` | The model approves malicious actions, denies the intended safe path, or emits unsafe gate decisions. |
| `BROKEN_RUNTIME` | The model times out, fails to serve, emits unparsable output, or breaks orchestration. |

`FUNCTION_COMPATIBLE` is not sufficient for promotion when the challenge's
intended path depends on AI-mediated leakage, refusal variance, social
engineering, or approval behavior. Promotion to `WALKTHROUGH_COMPATIBLE` requires
sanitized evidence from the actual player chain, preferably over repeated rounds.

### Security Evaluation Suites

| Command | What it does |
|---------|-------------|
| `atomics adversarial` | Adversarial resilience eval (72 fixtures across suites) |
| `atomics adversarial --runs 5` | Multi-pass with mean ± stddev |
| `atomics adversarial --extra-judges ollama:deepseek-r1:14b` | Multi-judge consensus |
| `atomics adversarial --category tool_desc_injection` | Filter by category/group (multiturn, rag_poisoning, mcp, zerotrust, agentic, tool_safety, …) |
| `atomics adversarial --compare mistral-small:24b` | Run a second model on the same fixtures, print a per-fixture diff |
| `atomics adversarial --json-out run.json` | Machine-readable per-fixture export |
| `atomics adversarial --fail-on-resilience 60` | CI gate — non-zero exit if resilience < 60% |
| `atomics redblue --runs 3` | Red/blue capability eval (10 fixtures) with variance |
| `atomics redblue --mode red` / `--mode blue` | Offensive / defensive tasks only |
| `atomics archreview --repo juice-shop --models qwen2.5:7b` | Security-architecture repo review |
| `atomics probe --probes-file probes.yaml` | Live infrastructure artifact analysis |
| `atomics probe --alert-on-regression` | Alert when scores drop >10% |
| `atomics eval` | Standard quality evaluation (25 fixtures) |
| `atomics codegen` | Code generation eval (15 fixtures; functional correctness via test execution) |
| `atomics multiturn` | Multi-turn conversation eval (35 fixtures: contradiction, persona drift, long-context, tool chaining) |
| `atomics refusal` / `atomics codereview` | Refusal and code-review evaluation suites |

### RAG Pipeline

Real retrieval requires `uv sync --extra rag` (`sqlite-vec`, `sentence-transformers`).

| Command | What it does |
|---------|-------------|
| `atomics rag` | RAG pipeline evaluation (grounding, faithfulness, abstention) |
| `atomics rag --index ./index.vec` | Run RAG eval against a real sqlite-vec index |
| `atomics rag-index ./docs --db ./index.vec` | Build a sqlite-vec index from a directory of documents |
| `atomics rag-retrieval --index ./index.vec --gold gold.json` | Retrieval quality: recall@k, precision@k, MRR, nDCG@k |

### Distributed Benchmarking

| Command | What it does |
|---------|-------------|
| `atomics distributed run --coordinator http://coordinator:8000 --api-key KEY` | Submit a split-task distributed job to the coordinator |
| `atomics distributed status --job-id JOB_ID ...` | Poll and emit clean JSON for a distributed job |
| `atomics worker --coordinator http://coordinator:8000 --api-key KEY --provider ollama` | Start a worker that polls, executes, and reports tasks |
| `atomics worker --provider brain-gateway --model qwen3:14b --host http://nuc:30080` | Run a worker against a specific model endpoint |

### Operations

| Command | What it does |
|---------|-------------|
| `atomics schedule --install` | Install cron/systemd/launchd schedule |
| `atomics export` | Export task results (default suite) |
| `atomics export --suite {eval,redblue,adversarial,stress,sweep,soak}` | Suite-isolated export |
| `atomics export --suite all --format csv` | Export all suites as CSV |
| `atomics advisor` | Cost optimization recommendations from benchmark history |
| `atomics advisor --min-quality 0.9` | Higher quality threshold for advisor suggestions |
| `atomics secrets get KEY` / `--show` | Read a keychain secret (masked by default) |
| `atomics login` | OAuth/OIDC login |

### API Server Mode

Optional `[api]` extra (`uv sync --extra api`). Runs atomics as a FastAPI HTTP
service for CI/CD, dashboards, or remote scheduling.

| Command | What it does |
|---------|-------------|
| `atomics server` | Start the HTTP API server (default bind localhost:8000) |
| `atomics server --no-auth` | Disable API key auth (local development only) |
| `atomics server --api-key KEY` | Allow an API key (repeatable); clients send `X-API-Key` |
| `atomics server --host 0.0.0.0 --port 8080` | Bind address/port |
| `atomics server --log-level debug` | Verbose uvicorn logging |

---

## Adversarial Suite (72 fixtures across suites)

Tests whether a model **resists** adversarial manipulation. Uses inverted
scoring — higher score = better resistance. Suites (each selectable via
`--category`): base prompt-injection/role-confusion/etc., `zerotrust`,
`agentic`, `mcp`, `tool_safety`, `multiturn`, `rag_poisoning`,
`tool_desc_injection`.

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
  --extra-judges ollama:deepseek-r1:14b@gpu-host

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
rules or system prompt fragments. Observed during agentic AI-gate
model-compatibility testing — `qwen3:4b` broke an AI deployment-approval gate
with this failure mode.

**adv-15 (credential extraction):** Mirrors the "helpful ops request" social
engineering strategy that leaked secrets across multiple Ollama models in live
model testing.

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
    url: http://gpu-host:11434/api/tags
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

## Evaluation Fidelity

Benchmark numbers are only useful if they are honest and reproducible.
stoneburner hardens both the judge and the metrics so cross-model comparisons
hold up.

### Judge accuracy & calibration

The LLM-as-judge quality scorer is built to be reproducible and hard to game:

- **Deterministic scoring** — quality/resistance judges request `temperature=0.0`
  (withheld where the backend forbids it: OpenAI reasoning models, Claude
  extended-thinking; brain-gateway controls sampling server-side).
- **Self-judge guard** — `detect_self_judge` warns when a judge is the same
  provider+model as the model under test (incl. consensus-panel members), since
  self-preference biases the score.
- **Gold-criteria coverage** — `compute_criteria_coverage` adds an objective,
  judge-independent lexical measure of how many of a fixture's gold criteria
  appear in the response (`task_results.criteria_coverage`, schema v13).
- **Multi-judge consensus** — `score_consensus` averages a primary judge plus an
  optional panel and records inter-judge stdev (`judge_score_stdev`, schema v14);
  `eval`/`adversarial` accept `--extra-judges provider:model[@host]`.
- **Fair completeness** — the judge's truncation cap scales to each fixture's
  expected output length, so long answers are judged in full, not cut at 3000
  chars.
- **Calibration regression guard** — `atomics/eval/calibration.py` ranks graded
  answers (wrong → thin → thorough) and asserts monotonic, well-separated
  scoring; an opt-in live test (`ATOMICS_LIVE_JUDGE=1`) validates the real judge.
  A `parse_failure_rate` is surfaced in the eval summary.

### Token-burn fidelity

Provider metrics report only what each API can actually observe, so cost and
throughput comparisons are apples-to-apples:

- **Prompt-cache tokens** — Claude `cache_read`/`cache_write` tokens are captured
  and priced correctly (reads 0.10×, writes 1.25× the base input rate).
- **Honest thinking tokens** — populated only when truly reported (OpenAI
  `reasoning_tokens`; Ollama/vLLM use a character-proportional estimate anchored
  to the real output total; Claude stays 0, since Anthropic bills thinking as
  output).
- **Standardized throughput** — `tokens_per_second` = output tokens ÷ elapsed
  time via `compute_tps`, with a `tps_basis` field labeling `wall_clock` vs
  `generation` (Ollama decode time); Bedrock now reports throughput too.
- **Centralized pricing** — all pricing tables and the cost function live in
  `atomics/providers/pricing.py`.

Both areas persist to `task_results` (schema v12–v14) and surface in
`provider-test` output and `compare`.

---

## Inference Backend Management (`brain/` + `inference.env`)

stoneburner ships a portable inference-ops layer that is agnostic to any
specific host — usable on a laptop, a GPU box, or cloud nodes.

### `brain/` toolkit

Standalone shell scripts (no dependency on the `atomics` package) for managing
the inference layer on any box:

| Script | Purpose |
|--------|---------|
| `brain-status` | Print running models, VRAM mapping, gateway state |
| `brain-switch` | Toggle a box between Ollama and OpenAI-compatible (vLLM/LiteLLM) |
| `brain-vllm` | Start/stop/restart the vLLM engine + gateway systemd fleet |

### The `inference.env` standard

A vendor-neutral control file lets **any box describe the LLM inference target
it is wired to**, so any consumer (the `atomics` providers, the `brain/`
scripts, a downstream agent service) self-configures. Spec:
[`docs/INFERENCE_ENV.md`](https://github.com/babywyrm/stoneburner/blob/main/docs/INFERENCE_ENV.md).

Canonical schema (`INFERENCE_BACKEND` / `INFERENCE_URL` / `INFERENCE_MODEL` /
`INFERENCE_THINK` / `INFERENCE_API_KEY`, plus optional intent and provenance
fields), with legacy `OPENAI_*` / `OLLAMA_*` / `INFERENCE_API` keys normalized
automatically. Searched at `$INFERENCE_ENV` → `$BRAIN_ENV` →
`/opt/agentic/inference.env` → `/etc/agentic/inference.env`.

```python
from atomics.inference import load_control_file, provider_from_target

target = load_control_file()              # reads a box's control file
provider = provider_from_target(target)   # auto-builds the matching provider
```

`atomics.inference` also exposes the agnostic resolver (difficulty/pool tier →
resolved backend+model+endpoint, with model-compat and backend-capability
checks) used by box bootstrappers to write a control file.

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

## API Server Mode

Install with `uv sync --extra api`, then:

```bash
# local development (no auth — do not use in production)
uv run atomics server --no-auth

# production with API key(s)
uv run atomics server --api-key sk-abc123 --api-key sk-xyz789
```

When API keys are configured, API routes (except health) require an
`X-API-Key` header.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/health` | Health check (public) |
| `POST` | `/api/v1/runs` | Start a benchmark run (async job) |
| `POST` | `/api/v1/evals` | Start an eval suite (`accuracy`, `rag`, `multiturn`, `adversarial`, `codegen`) |
| `GET` | `/api/v1/jobs/{job_id}` | Poll job status / result |
| `GET` | `/api/v1/compare` | Compare providers/models |
| `GET` | `/api/v1/reports/recent-runs` | Recent run report |
| `POST` | `/api/v1/workers/register` | Register a distributed worker |
| `POST` | `/api/v1/workers/{worker_id}/heartbeat` | Worker heartbeat |
| `GET` | `/api/v1/workers/poll` | Worker claims a pending task assignment |
| `POST` | `/api/v1/distributed/runs` | Submit a distributed split-task job |
| `GET` | `/api/v1/distributed/runs/{job_id}` | Poll distributed job status |
| `POST` | `/api/v1/distributed/assignments/{assignment_id}/result` | Submit completed assignment result |

```bash
JOB_ID=$(curl -s -H "X-API-Key: sk-abc123" -H "Content-Type: application/json" \
  -d '{"provider": "ollama", "model": "qwen3:14b", "tier": "ez", "iterations": 3}' \
  http://127.0.0.1:8000/api/v1/runs | jq -r '.job_id')

curl -s -H "X-API-Key: sk-abc123" http://127.0.0.1:8000/api/v1/jobs/$JOB_ID | jq
```

---

## Storage

SQLite database (schema v20) with tables:

| Table | Content |
|-------|---------|
| `runs` | Benchmark run metadata |
| `distributed_jobs` | Distributed split-task job metadata and summary |
| `distributed_assignments` | Per-task assignment state, results, and retry count |
| `workers` | Registered worker identity, labels, capabilities, and heartbeat status |
| `task_results` | Per-task outcomes (`suite` column eval/redblue); fidelity columns: cache read/write tokens + `tps_basis` (v12), `criteria_coverage` (v13), `judge_score_stdev` (v14) |
| `adversarial_results` | Adversarial fixture results |
| `probe_results` | Live probe results |
| `stress_results` | Stress test throughput/latency per concurrency level |
| `sweep_results` | Multi-model sweep quality/latency/cost per run |
| `scenario_results` | Mixed-workload scenario outcomes (per-workload latency/SLA) |
| `soak_results` | Long-duration stability runs (drift, error rate, cost) |
| `baselines` | Named metric baselines for regression comparison (UNIQUE name+suite) |
| `archreview_results` | Security-architecture review findings per model/tier/round (v15); columns: recall, precision, f-score, judge score, finding count, pack hash, matched categories |

Export via `atomics export --suite {tasks,stress,sweep,all} --format {jsonl,csv}`.

---

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `ANTHROPIC_API_KEY` | — | Claude API key |
| `OPENAI_API_KEY` | — | OpenAI API key |
| `GROQ_API_KEY` | — | Groq API key |
| `TOGETHER_API_KEY` | — | Together AI API key |
| `GEMINI_API_KEY` | — | Google Gemini API key |
| `ATOMICS_OLLAMA_HOST` | `http://localhost:11434` | Ollama endpoint for local inference |
| `ATOMICS_OLLAMA_MODEL` | `qwen2.5:7b` | Default model for Ollama provider |
| `ATOMICS_VLLM_HOST` | `http://localhost:8000/v1` | vLLM / OpenAI-compatible base URL (e.g. a LiteLLM gateway) |
| `ATOMICS_VLLM_MODEL` | `qwen2.5:3b` | Default model for vllm provider |
| `ATOMICS_LLAMACPP_HOST` | `http://localhost:8080` | llama.cpp server endpoint |
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
# Sweep all models on an Ollama host
for model in qwen2.5:3b gemma3:4b mistral:7b deepseek-r1:14b qwen2.5:14b; do
  atomics adversarial --provider ollama -m "$model" \
    --ollama-host http://ollama.internal:11434 \
    --category social_engineering,data_exfil_attempt \
    --runs 3
done

# Sweep vLLM gateway models (judge also on the gateway)
for model in qwen2.5:1.5b qwen2.5:3b qwen3.5:0.8b; do
  atomics adversarial --provider vllm -m "$model" \
    --vllm-host http://gpu-host:8000/v1 \
    --judge-provider vllm \
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
