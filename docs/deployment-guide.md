# Deployment Guide — Local, Cluster, and Cloud

This guide covers the practical differences between running the security stack
locally (Docker Compose), on a self-hosted cluster (K3s/K8s), and in cloud
environments (EKS/GKE/AKS). Each deployment type has different performance
characteristics, brain provider options, and recommended scan configurations.

---

## Deployment Comparison

| Dimension | Local (Docker Compose) | Self-Hosted Cluster (K3s/K8s) | Cloud (EKS/GKE/AKS) |
|---|---|---|---|
| **Setup time** | 2 minutes | 15 minutes | 30+ minutes |
| **Brain provider** | Claude API or Ollama | Claude API, Ollama, or Bedrock | Bedrock (recommended) |
| **nullfield** | Standalone proxy | Sidecar or gateway | Sidecar, gateway, or auto-inject |
| **Teleport** | Not available | Full stack | Full stack + real certs |
| **CRDs** | Not applicable | Supported | Supported |
| **mcpnuke scan speed** | 0.6s (static), 90s+ (invoke) | 0.6s (static), 90s+ (invoke) | 0.3s (static), 30s (invoke) |
| **Best for** | Development, learning | Lab testing, demos | Production validation |

---

## Local (Docker Compose)

### Start camazotz

```bash
git clone https://github.com/babywyrm/camazotz && cd camazotz

# Option A: Claude API (best lab quality, requires API key)
echo "ANTHROPIC_API_KEY=sk-ant-..." > compose/.env
make up

# Option B: Ollama (fully offline, no API cost, lower lab quality)
make up-local
```

### Brain provider impact on scan speed

The brain provider determines how fast tool calls execute, which directly
affects mcpnuke behavioral probe duration:

| Brain Provider | Tool Call Latency | Full Invoke Scan (5 tools) | Quality |
|---|---|---|---|
| Claude API (`cloud`) | 1-5s per call | 60-120s | Best — real guardrail behavior |
| Ollama local (`local`) | 0.5-2s per call | 20-40s | Good — depends on model/hardware |
| Bedrock (`bedrock`) | 0.3-1s per call | 15-30s | Best — low latency + real Claude |
| Stub (no LLM) | instant | 5s | None — labs return stub responses |

### Recommended scan modes for local

```bash
# Quick audit (instant, no tool invocation)
mcpnuke --targets http://localhost:8080/mcp --fast --no-invoke --verbose

# Generate defense policy (instant)
mcpnuke --targets http://localhost:8080/mcp --fast --no-invoke --generate-policy fix.yaml

# Deep behavioral scan (budget 2-3 minutes with Claude brain)
mcpnuke --targets http://localhost:8080/mcp --fast --probe-workers 2 --verbose

# With AI analysis of findings (adds ~30s for Claude reasoning)
mcpnuke --targets http://localhost:8080/mcp --fast --no-invoke --claude --verbose
```

### Running nullfield locally

nullfield runs as a standalone proxy in front of camazotz:

```bash
# Start nullfield's echo-server test environment
cd nullfield && docker compose up -d

# Or start nullfield as a proxy in front of camazotz:
docker run -p 9090:9090 -p 9091:9091 \
  -e NULLFIELD_UPSTREAM_ADDR=host.docker.internal:8080 \
  -v $(pwd)/examples/policy.yaml:/etc/nullfield/policy.yaml:ro \
  -v $(pwd)/examples/tools.yaml:/etc/nullfield/tools.yaml:ro \
  ghcr.io/babywyrm/nullfield:latest

# Scan through nullfield
mcpnuke --targets http://localhost:9090/mcp --fast --no-invoke --verbose
```

### Limitations

- No Teleport (requires Kubernetes for tbot/auth service)
- No CRDs (no K8s API)
- No auto-inject webhook (no admission controller)
- Tool invocation scans are slow due to Claude API round-trips

---

## Self-Hosted Cluster (K3s / K8s)

### Deploy the full stack

```bash
# Deploy camazotz with nullfield sidecar
cd camazotz && make helm-deploy

# Deploy nullfield CRDs
kubectl apply -f https://raw.githubusercontent.com/babywyrm/nullfield/main/deploy/crds/nullfieldpolicy-crd.yaml
kubectl apply -f https://raw.githubusercontent.com/babywyrm/nullfield/main/deploy/crds/toolregistry-crd.yaml

# (Optional) Deploy Teleport
# Follow: https://github.com/babywyrm/agentic-sec/blob/main/docs/teleport/setup.md
```

### Brain provider options

```yaml
# In Helm values.yaml:
config:
  brainProvider: "cloud"          # Claude API (best quality)
  # brainProvider: "local"        # Ollama (needs ollama pod)
  # brainProvider: "bedrock"      # AWS Bedrock (needs IRSA)
```

### Scan modes for clusters

```bash
# From outside the cluster (via NodePort)
mcpnuke --targets http://<NODE_IP>:30080/mcp --fast --no-invoke --verbose

# From inside the cluster (via ClusterIP)
mcpnuke --targets http://brain-gateway.camazotz.svc:8080/mcp --fast --no-invoke

# K8s service discovery (auto-find all MCP servers)
mcpnuke --k8s-discover --k8s-discover-namespaces camazotz hammerhand --verbose

# Generate and apply policy via CRD
mcpnuke --targets http://<NODE_IP>:30080/mcp --fast --no-invoke --generate-policy fix.yaml
kubectl apply -n camazotz -f fix.yaml

# Verify CRD applied
kubectl -n camazotz get nullfieldpolicies
```

### What's different from local

- **nullfield runs as a sidecar** — tool calls pass through policy enforcement
- **CRDs available** — `kubectl apply` your policies, hot-reload works
- **Teleport available** — machine identity, K8s access, MCP App Access
- **Auto-inject webhook** — annotate pods with `nullfield.io/inject: "true"`
- **Scan includes Teleport checks** — proxy discovery, cert validation, bot RBAC

### K3s single-node notes

For a single-node K3s cluster (replace `<NODE_IP>` with your node's IP):

```bash
# NodePorts:
#   30080 — brain-gateway (through nullfield sidecar)
#   30136 — Teleport proxy

# Scan with Teleport checks (use node IP so proxy discovery works)
mcpnuke --targets http://<NODE_IP>:30080/mcp --fast --no-invoke --verbose

# tbot kubeconfig for agent access testing
kubectl -n teleport get secret tbot-kube -o jsonpath="{.data.kubeconfig\.yaml}" | base64 -d > /tmp/agent-kubeconfig.yaml
KUBECONFIG=/tmp/agent-kubeconfig.yaml kubectl --insecure-skip-tls-verify get pods -A
```

---

## Cloud (EKS / GKE / AKS)

### Key differences

| Feature | Self-Hosted | Cloud |
|---|---|---|
| TLS certificates | Self-signed (lab only) | cert-manager + Let's Encrypt or ACM |
| Teleport | Self-signed proxy | Real domain + ACME certs |
| Brain provider | Claude API or Ollama | Bedrock via IRSA (recommended) |
| Ingress | NodePort | ALB/NLB with WAF |
| Secrets | K8s Secrets | AWS Secrets Manager / GCP Secret Manager |

### Bedrock configuration (AWS)

```yaml
# Helm values for Bedrock brain:
config:
  brainProvider: "bedrock"
  model: "anthropic.claude-sonnet-4-20250514-v1:0"
  awsRegion: "us-east-1"
  # No API key needed — uses IRSA for auth
```

Bedrock provides the lowest latency for tool calls (~300ms vs 1-5s for Claude
API), making behavioral scans significantly faster.

### Production scan workflow

```bash
# Static audit (safe for production — no tool invocation)
mcpnuke --targets https://mcp.internal.example.com/mcp \
  --no-invoke \
  --auth-token "$MCP_TOKEN" \
  --tls-verify \
  --generate-policy recommended.yaml \
  --json audit-report.json \
  --verbose

# Compare against baseline (CI/CD regression gate)
mcpnuke --targets https://mcp.internal.example.com/mcp \
  --no-invoke \
  --auth-token "$MCP_TOKEN" \
  --baseline previous-baseline.json \
  --save-baseline current-baseline.json

# K8s-native discovery scan
mcpnuke \
  --k8s-discover \
  --k8s-discover-namespaces mcp-prod mcp-staging \
  --k8s-token-file /var/run/secrets/kubernetes.io/serviceaccount/token \
  --no-invoke \
  --generate-policy recommended.yaml
```

### Real domain for Teleport

In cloud environments, point a real domain at the Teleport proxy (ALB/NLB)
and use ACME for certificates. This eliminates the `/etc/hosts` workaround
and the `--insecure` flag:

```yaml
# teleport-cluster Helm values for cloud:
clusterName: teleport.example.com
proxyListenerMode: multiplex
acme: true
acmeEmail: security@example.com
```

---

## Performance Tuning

### Scan speed optimization

| Flag | Effect | When to Use |
|------|--------|-------------|
| `--fast` | Sample top 5 tools, skip heavy probes | Always for initial scans |
| `--no-invoke` | Skip all tool calls | Quick audit, CI/CD gates |
| `--probe-workers 2` | Parallel behavioral probes | When invoke scan is slow |
| `--deterministic` | Stable ordering, single-thread | Benchmarking, regression |
| `--claude` | AI analysis of findings | Deep investigation |

### Expected scan times

| Configuration | Local (Claude) | Local (Ollama) | Cluster | Cloud (Bedrock) |
|---|---|---|---|---|
| `--fast --no-invoke` | 0.6s | 0.6s | 0.6s | 0.3s |
| `--fast --no-invoke --claude` | 27s | n/a | 27s | 15s |
| `--fast` (with invoke) | 90-120s | 20-40s | 90-120s | 15-30s |
| Full scan (no --fast) | 10+ min | 3-5 min | 10+ min | 2-3 min |

### Brain provider selection guide

| Scenario | Recommended Provider | Why |
|---|---|---|
| Learning / development | Claude API (`cloud`) | Best guardrail behavior for labs |
| Offline / air-gapped | Ollama (`local`) | No internet needed |
| CI/CD pipeline | Stub or Ollama | Fast, deterministic, no API cost |
| Production validation | Bedrock | Low latency, IAM-native, no API keys |
| Cost-sensitive | Ollama with qwen3:4b | Free, good quality for most labs |
