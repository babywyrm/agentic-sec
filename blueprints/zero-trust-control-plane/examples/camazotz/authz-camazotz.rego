# Zero-Trust Control Plane — runtime authz policy, mapped to a REAL target.
#
# This is the same PDP contract as ../../policy/authz.rego (package envoy.authz,
# entry data.envoy.authz.allow, DENY BY DEFAULT) — but the tool_grants are mapped
# to the actual MCP tools exposed by the camazotz MCP Security Playground
# (brain-gateway, 138 tools across 52 OWASP-MCP-Top-10 labs).
#
# The point this proves: camazotz's core lesson is that the LLM guardrail can be
# talked past — the model may "refuse" in its reasoning while the tool logic runs
# the dangerous action anyway. This policy sits OUT OF BAND at the MCP transport
# (Envoy/waypoint ext_authz), so a `tools/call` to a credential-reading or
# RCE-ish tool is denied deterministically BEFORE brain-gateway/the LLM ever runs.
#
# One OPA corpus governs multiple PEPs/namespaces (shared PDP): the generic echo
# grants and the camazotz grants coexist — different tool names, no conflict.

package envoy.authz

import rego.v1

default allow := false

principal := p if {
	p := input.attributes.request.http.headers["x-principal"]
}

mcp := body if {
	raw := input.attributes.request.http.body
	raw != ""
	body := json.unmarshal(raw)
}

# Benign protocol methods — handshake/enumeration, no side effects.
benign_methods := {"initialize", "tools/list", "resources/list", "prompts/list", "ping", "notifications/initialized"}

allow if {
	mcp.method in benign_methods
}

allow if {
	mcp.method == "tools/call"
	tool := mcp.params.name
	tool in tool_grants[principal]
}

# ── Authorization data (principal → allowed tools) ───────────────────────────
# Least-privilege grants aligned to camazotz's agent scenarios. Every dangerous
# tool (credential read, secret extraction, query exec, system-prompt rewrite,
# identity replay, arbitrary egress) is intentionally absent → default deny.
tool_grants := {
	# Generic teaching demo (echo-server) — kept so one policy serves both.
	"ci-deployer": {
		"get_status", "list_pods", "scale_deployment",
		# camazotz: a CI/CD deploy agent legitimately inspects topology and runs
		# code-review checks. It has NO business reading credentials or secrets.
		"chain.get_service_manifest", "code_review.submit_pr",
		"code_review.run_checks", "code_review.get_report",
		"gateway.list_resources",
	},
	"support-bot": {
		"get_status", "read_ticket",
		# camazotz: a customer-support bot is read-only over audit/comms.
		"audit.list_actions", "comms.list_sent",
		"schema.list_surface", "ratelimit.check_budget",
	},
	"readonly-observer": {
		"get_status", "list_pods",
		"chain.read_audit_log", "audit.list_actions", "schema.list_surface",
	},
}

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
