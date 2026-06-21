#!/usr/bin/env python3
"""drive-flows — push representative agentic flows through the zero-trust stack
and record, per flow, exactly what each layer of the control plane delivered.

Each flow is designed to be decided by ONE specific layer so you can see that
layer's unique contribution:

  OPA waypoint (Phase A)   coarse per-principal tool authz       (allow / deny)
  nullfield   (Phase E)    MCP-aware actions                     (allow/deny/hold/scope)
  AI gateway  (Phase D)    model egress allowlist                (allow / deny)

Gatekeeper (Phase B, admission) and NetworkPolicy (Phase C, L3/L4) are deploy/
network-time and are recorded as proven capabilities, not per-request flows.

Run on a host with kubectl + curl access to the cluster (e.g. the node):
  python3 drive-flows.py > flows.json

Endpoints (override via env):
  PEP_URL   nullfield policed MCP   (default http://127.0.0.1:30090/mcp)
  AIGW_URL  AI gateway              (default http://127.0.0.1:80/v1/chat/completions ... set to node IP)
  NS        camazotz namespace      (default camazotz)
"""
import json, os, subprocess, time, datetime

PEP_URL = os.environ.get("PEP_URL", "http://127.0.0.1:30090/mcp")
AIGW_URL = os.environ.get("AIGW_URL", "http://127.0.0.1/v1/chat/completions")
NS = os.environ.get("NS", "camazotz")
KUBECTL = os.environ.get("KUBECTL", "kubectl")


def sh(args, timeout=40):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except Exception as e:  # noqa: BLE001
        return f"__err__:{e}"


def mcp_body(tool):
    return json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                       "params": {"name": tool, "arguments": {}}})


def curl_json(url, body, principal, timeout=30, headers=None):
    cmd = ["curl", "-s", "-m", str(timeout), "-w", "\n%{http_code}",
           "-H", "Content-Type: application/json", "-H", "Accept: application/json",
           "-H", f"x-principal: {principal}", "-X", "POST", url, "-d", body]
    for h in headers or []:
        cmd[1:1] = ["-H", h]
    out = sh(cmd, timeout + 5)
    parts = out.rsplit("\n", 1)
    code = parts[-1] if len(parts) > 1 else "000"
    payload = parts[0] if len(parts) > 1 else out
    decision, reason = "ALLOW", ""
    try:
        j = json.loads(payload)
        if isinstance(j, dict) and "error" in j:
            c = j["error"].get("code")
            msg = j["error"].get("message", "")
            reason = msg
            decision = {(-32000): "DENY", (-32005): "HOLD", (-32003): "DENY"}.get(c, "DENY")
        elif "No matching route" in payload:
            decision, reason = "DENY", "egress model not in allowlist"
    except Exception:  # noqa: BLE001
        if "No matching route" in payload:
            decision, reason = "DENY", "egress model not in allowlist"
    return {"http": code, "decision": decision, "reason": reason[:160], "body": payload[:240]}


def opa_via_mesh(tool, principal):
    """Exercise the OPA waypoint by calling the in-mesh Service from a dbg pod."""
    body = mcp_body(tool)
    code = sh([KUBECTL, "-n", NS, "exec", "dbg", "--",
               "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "-m", "10",
               "-X", "POST", "http://brain-gateway:8080/mcp",
               "-H", "Content-Type: application/json", "-H", "Accept: application/json",
               "-H", f"x-principal: {principal}", "-d", body], 25)
    decision = "ALLOW" if code == "200" else ("DENY" if code == "403" else "?")
    return {"http": code, "decision": decision,
            "reason": "OPA: principal granted tool" if decision == "ALLOW" else "OPA: default-deny (no grant)"}


# ── flow definitions ─────────────────────────────────────────────────────────
RESULTS = {"generated": datetime.datetime.utcnow().isoformat() + "Z", "flows": []}


def add(fid, title, layer, principal, target, res, intent):
    RESULTS["flows"].append({"id": fid, "title": title, "layer": layer,
                             "principal": principal, "target": target, "intent": intent, **res})


# OPA waypoint layer (Phase A) — per-principal authz
add("opa-allow", "Granted principal runs a granted tool", "OPA waypoint", "ci-deployer",
    "code_review.run_checks", opa_via_mesh("code_review.run_checks", "ci-deployer"),
    "A CI agent runs its allowed code-review tool.")
add("opa-deny", "Unknown principal blocked at the mesh", "OPA waypoint", "unknown",
    "get_status", opa_via_mesh("get_status", "unknown"),
    "An unidentified caller is rejected before the workload.")

# nullfield layer (Phase E) — MCP-aware actions
add("nf-allow", "Benign read is forwarded", "nullfield", "ci-deployer",
    "chain.get_service_manifest", curl_json(PEP_URL, mcp_body("chain.get_service_manifest"), "ci-deployer"),
    "Agent reads service topology — safe, allowed.")
add("nf-deny", "RCE-class tool blocked", "nullfield", "attacker",
    "egress.fetch_url", curl_json(PEP_URL, mcp_body("egress.fetch_url"), "attacker", 15),
    "Agent attempts SSRF/exfil — denied by policy.")
add("nf-scope", "Credential read is sanitized", "nullfield", "ci-deployer",
    "cred_broker.read_credential", curl_json(PEP_URL, mcp_body("cred_broker.read_credential"), "ci-deployer"),
    "Agent reads a credential — args stripped, secrets redacted in response.")
add("nf-hold", "System-prompt change held for approval", "nullfield", "attacker",
    "config.update_system_prompt", curl_json(PEP_URL, mcp_body("config.update_system_prompt"), "attacker", 20),
    "Agent tries to rewrite its own system prompt — parked for a human.")

# AI egress layer (Phase D) — model allowlist
add("aigw-allow", "Allowlisted model egresses", "AI gateway", "agent",
    "qwen3:4b", curl_json(AIGW_URL, json.dumps({"model": "qwen3:4b", "messages": [{"role": "user", "content": "hi"}], "stream": False}), "agent", 60),
    "Agent calls the approved model — proxied to the LLM.")
add("aigw-deny", "Non-allowlisted model refused", "AI gateway", "agent",
    "llama3.2:1b", curl_json(AIGW_URL, json.dumps({"model": "llama3.2:1b", "messages": [{"role": "user", "content": "hi"}], "stream": False}), "agent", 20),
    "Agent calls a model that exists in the backend but is not allowlisted.")

print(json.dumps(RESULTS, indent=2))
