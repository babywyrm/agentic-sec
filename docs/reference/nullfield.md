# nullfield Quick Reference

Lightweight MCP arbiter proxy. One binary, one YAML policy.

**Repo:** [github.com/babywyrm/nullfield](https://github.com/babywyrm/nullfield)

**In the framework:** nullfield is the per-cell policy enforcer in the
[Identity Flow Framework](../identity-flows.md). Each of the five actions
below maps to typical defaults for one or more identity lanes — see the
"Per-Lane Default Actions" table in the framework.

## The Five Actions

| Action | What Happens | When to Use |
|--------|-------------|-------------|
| ALLOW | Forward immediately | Safe read-only tools |
| DENY | Reject immediately | Dangerous tools, default policy |
| HOLD | Park for human approval | Deployments, agent delegation |
| SCOPE | Allow but modify | Strip secrets from args, redact response PII |
| BUDGET | Allow but rate-limit | Expensive LLM calls, cost control |

BUDGET is expressed in policy as `action: ALLOW` with a `budget:` block
(not as a standalone action constant).

## Deployment Modes

| Mode | How | When |
|------|-----|------|
| Sidecar | Container next to your MCP server pod | Default — one nullfield per pod |
| Gateway | Single instance, multiple upstreams | Centralized enforcement for multiple MCP servers |
| Controller | Cluster-wide gRPC service for shared holds, budgets, events | Multi-pod coordination |
| Auto-inject | `nullfield.io/inject: "true"` annotation | Platform teams — zero-touch sidecar injection |

## Policy YAML

```yaml
apiVersion: nullfield.io/v1alpha1
kind: NullfieldPolicy
metadata:
  name: my-policy
spec:
  selector:
    matchLabels:
      app: brain-gateway
  rules:
    - action: ALLOW
      toolNames: [cost.check_usage]
    - action: ALLOW
      toolNames: [config.ask_agent]
      budget:
        perIdentity: { maxCallsPerHour: 20 }
        perSession: { maxCallsPerHour: 10 }
    - action: HOLD
      toolNames: [delegation.invoke_agent]
      hold: { timeout: "5m", onTimeout: DENY }
    - action: SCOPE
      toolNames: [db.query]
      scope:
        response:
          redactPatterns: [password, secret, api_key]
    - action: DENY
      toolNames: ["*"]
```

## JSON-RPC Error Codes

| Code | Meaning |
|------|---------|
| `-32000` | Policy denied |
| `-32001` | Identity verification failed |
| `-32002` | Circuit breaker tripped |
| `-32003` | Tool not registered / route not found |
| `-32004` | Budget exhausted / velocity limit |
| `-32005` | Hold timeout |
| `-32006` | Scope modification error |
| `-32007` | Response inspection violation |

## mcpnuke Integration

```bash
mcpnuke --targets http://brain-gateway:8080 --generate-policy policy.yaml
kubectl apply -f policy.yaml
mcpnuke --targets http://brain-gateway:30090 --fast
```

mcpnuke scans produce nullfield-compatible `NullfieldPolicy` YAML. The
generated policy maps finding severity to actions: DENY for remote access
and exfil, HOLD for code execution, SCOPE for credential exposure, and
ALLOW+budget for rate-limit findings. Deploy the generated policy, re-scan
through the policed path to verify enforcement.

## Key Commands

```bash
# Docker Compose
docker compose up -d

# Kubernetes (raw manifests)
kubectl apply -f deploy/manifests/

# Kubernetes (Helm)
helm install nullfield deploy/helm/nullfield/

# CRDs
kubectl apply -f deploy/crds/
kubectl apply -f policy.yaml

# Controller
go build -o bin/nullfield-controller ./cmd/nullfield-controller

# Smoke test
bash tests/smoke.sh
```

## Configuration

All configuration is via environment variables (no CLI flags).

| Variable | Default | Purpose |
|----------|---------|---------|
| `NULLFIELD_LISTEN_ADDR` | `:9090` | Proxy listen address |
| `NULLFIELD_UPSTREAM_ADDR` | `localhost:8080` | Upstream MCP server |
| `NULLFIELD_ADMIN_ADDR` | `:9091` | Admin/metrics/health |
| `NULLFIELD_POLICY_PATH` | `/etc/nullfield/policy.yaml` | Policy file |
| `NULLFIELD_REGISTRY_PATH` | `/etc/nullfield/tools.yaml` | Tool registry |
| `NULLFIELD_ROUTES_PATH` | (empty) | Gateway mode routes |
| `NULLFIELD_IDENTITY_HEADER` | `Authorization` | Identity header name |
| `NULLFIELD_CIRCUIT_MAX_CALLS` | `100` | Circuit breaker limit |
| `NULLFIELD_CIRCUIT_MAX_DURATION` | `5m` | Circuit breaker window |
| `NULLFIELD_AUDIT_ENDPOINT` | (empty) | OTLP gRPC endpoint |
| `NULLFIELD_CONTROLLER_ADDR` | (empty) | Controller gRPC address |
| `NULLFIELD_VAULT_ADDR` | (empty) | Vault credential provider |

## Camazotz Integration

| Port | Service | Purpose |
|------|---------|---------|
| `:30080` | brain-gateway (bypass) | Direct MCP access |
| `:30090` | brain-gateway-policed | nullfield-enforced MCP |
| `:31591` | brain-gateway-policed admin | Sidecar admin/metrics |

- **138 tools** registered in `integrations/camazotz/tools.yaml`
- Three-tier policy: read-only ALLOW, write ALLOW, dangerous DENY
- Sync check: `bash integrations/camazotz/sync-tools.sh http://<host>:8080/mcp`

## Versions

| Version | Feature |
|---------|---------|
| v0.1-v0.4 | ALLOW, DENY, HOLD, SCOPE, BUDGET |
| v0.5 | OTLP traces, anomaly detection |
| v0.6 | Controller pod, universal Helm chart |
| v0.7 | Vault credentials, gateway mode, admission webhook |
| v0.8 | CRD controller (NullfieldPolicy as K8s resource) |
| v0.9 | Response inspection, tool lifecycle/rug-pull detection, per-identity cost attribution, 138-tool camazotz sync |
