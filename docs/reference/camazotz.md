# camazotz Quick Reference

MCP security playground — 52 intentionally vulnerable labs.

**Repo:** [github.com/babywyrm/camazotz](https://github.com/babywyrm/camazotz)

**In the framework:** every camazotz lab targets one cell of the
[Identity Flow Framework](../identity-flows.md). The "Lab Categories" table
below already groups labs roughly by lane — see the framework's "camazotz —
Per‑Lane Lab Coverage" table for the explicit mapping.

## Lab Categories

| Category | Labs | What They Teach |
|----------|------|----------------|
| **Auth** | auth_lab, oauth_delegation_lab, revocation_lab, rbac_lab | Token theft, audience bypass, revocation gaps, RBAC bypass |
| **Injection** | context_lab, indirect_lab, config_lab, blocklist_bypass_lab | Prompt injection, indirect injection, config tampering, incomplete input filter bypass |
| **Exfiltration** | secrets_lab, egress_lab, comms_lab, shadow_lab | Secret leakage, SSRF, multi-step exfil, webhook persistence |
| **Governance** | tool_lab, hallucination_lab, delegation_chain_lab, supply_lab, ai_governance_bypass_lab | Rug-pull, HITL bypass, delegation depth, supply chain, AI gate structural bypass |
| **Operations** | cost_exhaustion_lab, attribution_lab, error_lab, temporal_lab | Cost abuse, attribution forging, error disclosure, temporal drift |
| **Identity** | tenant_lab, credential_broker_lab, pattern_downgrade_lab, notification_lab, shared_idp_pollution_lab, dpop_forgery_lab | Cross-tenant, credential theft, auth downgrade, malicious notifications, shared IdP cross-pollution, DPoP forgery |
| **Teleport** | bot_identity_theft_lab, teleport_role_escalation_lab, cert_replay_lab | Bot cert theft, role escalation, expired cert replay |
| **Defense** | policy_authoring_lab, response_inspection_lab, budget_tuning_lab | Write nullfield policy, craft redaction rules, tune rate limits |

## Difficulty Levels

| Level | LLM Behavior | Exploit Difficulty |
|-------|-------------|-------------------|
| Easy | LLM cooperates, minimal guardrails | Exploits succeed easily |
| Medium | LLM has some restrictions, validation present | Requires crafting inputs |
| Hard | LLM refuses, strict validation, defenses active | Exploits blocked by defenses |

## Deployment Options

```bash
# Local with Claude API
make env && make up

# Local with Ollama (offline)
make up-local

# Kubernetes (Helm)
make helm-deploy

# With ZITADEL identity provider (bundled in compose)
# Set CAMAZOTZ_IDP_PROVIDER=zitadel in values

# With external Okta identity provider
make up-okta
```

## Runtime IdP Switching

The identity provider can be changed at runtime without restarting services,
via `PUT /config` or the Identity Dashboard UI. Switching provider
automatically resets all lab state to prevent stale token references.

```bash
# Switch to Okta at runtime
curl -s -X PUT http://localhost:8080/config \
  -H "Content-Type: application/json" \
  -d '{
    "idp": {
      "provider": "okta",
      "issuer_url": "https://dev-12345678.okta.com/oauth2/default",
      "token_endpoint": "https://dev-12345678.okta.com/oauth2/default/v1/token",
      "introspection_endpoint": "https://dev-12345678.okta.com/oauth2/default/v1/introspect",
      "revocation_endpoint": "https://dev-12345678.okta.com/oauth2/default/v1/revoke",
      "client_id": "your-client-id",
      "client_secret": "your-client-secret"
    }
  }'

# Switch back to mock
curl -s -X PUT http://localhost:8080/config \
  -H "Content-Type: application/json" \
  -d '{"idp": {"provider": "mock"}}'
```

The portal's Identity Dashboard (`/identity`) also exposes a switcher panel
with dropdown and endpoint fields. The global status strip includes a
clickable IdP pill for quick mock/zitadel/okta toggling.

## Key Endpoints

| Endpoint | What |
|----------|------|
| `http://localhost:3000` | Portal (Web UI) |
| `http://localhost:3000/challenges` | Challenge grid with flag submission |
| `http://localhost:3000/operator` | Guided walkthroughs (hidden) |
| `http://localhost:3000/identity` | Identity dashboard — status, runtime IdP switcher, architecture reference |
| `http://localhost:3000/lanes` | **Agentic Lane View** — labs grouped by identity lane (HTML) |
| `http://localhost:3000/threat-map` | Labs grouped by attack category (HTML) |
| `http://localhost:8080/mcp` | MCP JSON-RPC endpoint |
| `http://localhost:3000/api/lanes` | **Lane taxonomy** — schema v1 JSON (consumed by `mcpnuke --coverage-report`). Served by the portal on `:3000`, not brain-gateway. |
| `http://localhost:8080/health` | Health check |
| `PUT http://localhost:8080/config` | Runtime config (difficulty, brain model, IdP) |
| `POST http://localhost:8080/reset` | Reset all lab state |

### Kubernetes NodePort entry points

When deployed via `kube/brain-gateway-policed.yaml`, two NodePorts surface
the brain gateway with different enforcement postures:

| NodePort | Path | Behaviour |
|----------|------|-----------|
| `:30080` | direct → brain-gateway `:8080` | **Bypass** — raw target, no policy. Use for red-team scans. |
| `:30090` | nullfield sidecar `:9090` → brain-gateway | **Policed** — every call goes through nullfield identity + policy. Unauthenticated calls return JSON-RPC `-32001 identity verification failed`. |
| `:31591` | nullfield admin `:9091` | Policy CRD status, decision counters, audit tail. |

Smoke target: `make smoke-k8s-policed` in camazotz exercises the policed
path end-to-end.

## MCP Protocol

All tool interaction uses JSON-RPC 2.0 over HTTP:

```bash
# List all tools
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'

# Call a tool
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{
    "name":"auth.issue_token",
    "arguments":{"username":"admin","role":"admin","reason":"testing"}}}'

# Verify a flag
curl -s -X POST http://localhost:8080/api/flags/verify \
  -H "Content-Type: application/json" \
  -d '{"threat_id":"MCP-T04","flag":"CZTZ{...}"}'
```
