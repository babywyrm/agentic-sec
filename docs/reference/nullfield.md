# nullfield Quick Reference

Lightweight MCP arbiter proxy. One binary, one YAML policy.

**Repo:** [github.com/babywyrm/nullfield](https://github.com/babywyrm/nullfield)

## The Five Actions

| Action | What Happens | When to Use |
|--------|-------------|-------------|
| ALLOW | Forward immediately | Safe read-only tools |
| DENY | Reject immediately | Dangerous tools, default policy |
| HOLD | Park for human approval | Deployments, agent delegation |
| SCOPE | Allow but modify | Strip secrets from args, redact response PII |
| BUDGET | Allow but rate-limit | Expensive LLM calls, cost control |

## Deployment Modes

| Mode | How | When |
|------|-----|------|
| Sidecar | Container next to your MCP server pod | Default — one nullfield per pod |
| Gateway | Single instance, multiple upstreams | Centralized enforcement for multiple MCP servers |
| Auto-inject | `nullfield.io/inject: "true"` annotation | Platform teams — zero-touch sidecar injection |

## Policy YAML

```yaml
apiVersion: nullfield.io/v1alpha1
kind: NullfieldPolicy
metadata:
  name: my-policy
spec:
  rules:
    - action: ALLOW
      toolNames: [cost.check_usage]
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

# Smoke test
bash tests/smoke.sh
```

## Versions

| Version | Feature |
|---------|---------|
| v0.1-v0.4 | ALLOW, DENY, HOLD, SCOPE, BUDGET |
| v0.5 | OTLP traces, anomaly detection |
| v0.6 | Controller pod, universal Helm chart |
| v0.7 | Vault credentials, gateway mode, admission webhook |
| v0.8 | CRD controller (NullfieldPolicy as K8s resource) |
| v0.9 | Hot policy reload, response inspection |
