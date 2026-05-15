# Okta Developer Setup for camazotz

Configure an Okta Developer org as the identity provider for camazotz labs.
This replaces the bundled ZITADEL instance with external Okta, letting you
test Lane 1 (human-direct) and Lane 2 (delegated) identity flows against a
production-grade IdP.

---

## Prerequisites

- Free Okta Developer account ([developer.okta.com](https://developer.okta.com))
- camazotz cloned and running locally (`make up` works)

---

## 1. Create an Okta Developer org

Sign up at [developer.okta.com/signup](https://developer.okta.com/signup/).
After activation you'll have a domain like `https://dev-12345678.okta.com`.

## 2. Create an API Services application

1. In the Okta Admin Console, go to **Applications > Create App Integration**
2. Select **API Services** (machine-to-machine / client credentials)
3. Name it `camazotz-gateway`
4. Copy the **Client ID** and **Client Secret**

## 3. Configure the authorization server

By default Okta provides a `default` authorization server at:

```
https://dev-12345678.okta.com/oauth2/default
```

This supports custom scopes and audience. The endpoints are:

| Endpoint | URL |
|----------|-----|
| Issuer | `https://dev-12345678.okta.com/oauth2/default` |
| Token | `https://dev-12345678.okta.com/oauth2/default/v1/token` |
| Introspection | `https://dev-12345678.okta.com/oauth2/default/v1/introspect` |
| Revocation | `https://dev-12345678.okta.com/oauth2/default/v1/revoke` |

To verify, check OIDC discovery:

```bash
curl -s https://dev-12345678.okta.com/oauth2/default/.well-known/openid-configuration | jq .
```

## 4. Add custom scopes (optional)

Under **Security > API > Authorization Servers > default > Scopes**, add:

- `mcp:read` — read-only MCP tool access
- `mcp:write` — write MCP tool access
- `mcp:admin` — administrative tool access

These map to nullfield policy `when.claims.scope` conditions.

## 5. Configure camazotz

```bash
cd camazotz
cp compose/.env.okta.example compose/.env.okta
```

Edit `compose/.env.okta` with your values:

```env
OKTA_ISSUER_URL=https://dev-12345678.okta.com/oauth2/default
OKTA_TOKEN_ENDPOINT=https://dev-12345678.okta.com/oauth2/default/v1/token
OKTA_INTROSPECTION_ENDPOINT=https://dev-12345678.okta.com/oauth2/default/v1/introspect
OKTA_REVOCATION_ENDPOINT=https://dev-12345678.okta.com/oauth2/default/v1/revoke
OKTA_CLIENT_ID=0oa1234567890abcdef
OKTA_CLIENT_SECRET=your-client-secret-here
```

## 6. Start camazotz with Okta

```bash
make up-okta
```

This disables the bundled ZITADEL/Postgres containers and points
brain-gateway at your external Okta org.

Verify:

```bash
curl -s http://localhost:8080/config | jq '{idp_provider, idp_degraded, idp_reason}'
```

Expected output:

```json
{
  "idp_provider": "okta",
  "idp_degraded": false,
  "idp_reason": "ok"
}
```

If `idp_degraded` is `true`, Okta is unreachable and labs fall back to mock.

## 7. Configure nullfield for Okta

nullfield is already IdP-agnostic. Add an Okta provider to your policy:

```yaml
spec:
  identity:
    enabled: true
    providers:
      - name: okta
        issuer: "https://dev-12345678.okta.com/oauth2/default"
        jwksUri: "https://dev-12345678.okta.com/oauth2/default/v1/keys"
        audiences: ["api://default"]
```

See `nullfield/examples/policy-identity.yaml` for a complete multi-provider
example (Okta + ZITADEL side by side).

## 8. Scan with mcpnuke

mcpnuke is IdP-agnostic. Point it at the gateway as usual:

```bash
mcpnuke --targets http://localhost:8080/mcp --fast --no-invoke --verbose
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `idp_degraded: true` | Okta unreachable | Check network, verify issuer URL |
| `idp_provider: mock` | Missing `CAMAZOTZ_IDP_TOKEN_ENDPOINT` | Ensure `.env.okta` is loaded |
| Token endpoint 401 | Wrong client credentials | Regenerate secret in Okta Admin |
| Introspection returns `active: false` | Token expired or wrong audience | Check `aud` claim matches authorization server |
