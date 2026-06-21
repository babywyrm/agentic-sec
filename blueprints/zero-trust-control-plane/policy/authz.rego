# Zero-Trust Agentic Control Plane — runtime tool-call authorization policy.
#
# This is the Policy Decision Point (PDP). It is evaluated by OPA via the
# Envoy external-authorization gRPC plugin on EVERY request that reaches the
# gateway. Envoy is the Policy Enforcement Point (PEP); this policy is the brain.
#
# Posture: DENY BY DEFAULT. A request is allowed only if a rule below explicitly
# permits it. This is the core zero-trust property — absence of a grant is a deny.
#
# Entry point: data.envoy.authz.allow  (wired via the opa-envoy plugin `path`).

package envoy.authz

import rego.v1

# ── Default posture ──────────────────────────────────────────────────────────
default allow := false

# ── Principal identity ───────────────────────────────────────────────────────
# Phase 1: identity is asserted via the `x-principal` header (NOT trustworthy on
#          its own — fine for proving the policy path).
# Phase 3: this is replaced by the verified SPIFFE SVID / mTLS peer identity, so
#          the principal can no longer be spoofed by a header.
principal := p if {
	p := input.attributes.request.http.headers["x-principal"]
}

# ── Parse the MCP JSON-RPC request body ──────────────────────────────────────
# Envoy buffers the body and passes it as a string (ext_authz with_request_body).
# If the body is absent or not valid JSON, `mcp` is undefined and every
# body-dependent rule below fails closed → default deny.
mcp := body if {
	raw := input.attributes.request.http.body
	raw != ""
	body := json.unmarshal(raw)
}

# ── Allow benign, read-only MCP protocol methods ─────────────────────────────
# Handshake and enumeration carry no side effects; allow them so clients can
# discover the server. tools/call is the only method with side effects.
benign_methods := {"initialize", "tools/list", "resources/list", "prompts/list", "ping", "notifications/initialized"}

allow if {
	mcp.method in benign_methods
}

# ── Gate tools/call per-principal ────────────────────────────────────────────
# A tool invocation is permitted only when the requesting principal has been
# explicitly granted that specific tool. Everything else falls through to deny.
allow if {
	mcp.method == "tools/call"
	tool := mcp.params.name
	tool in tool_grants[principal]
}

# ── Authorization data (principal → allowed tools) ───────────────────────────
# Inlined here for the prototype. In production this comes from an OPA bundle or
# an external data document (data.json), and the principal key is the SVID path
# rather than a header value. Keep grants least-privilege and explicit.
tool_grants := {
	"ci-deployer": {"get_status", "list_pods", "scale_deployment"},
	"support-bot": {"get_status", "read_ticket"},
	"readonly-observer": {"get_status", "list_pods"},
}

# ── Decision log annotation (visible in OPA decision logs) ───────────────────
# Helps demos and audit: why was this allowed/denied?
reason := "benign MCP method" if {
	mcp.method in benign_methods
}

reason := sprintf("tools/call %q granted to %q", [mcp.params.name, principal]) if {
	allow
	mcp.method == "tools/call"
}

reason := "denied: no matching grant (default deny)" if {
	not allow
}
