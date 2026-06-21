# Phase F — offensive validation with mcpnuke (before / after)

The control plane's claims are only worth what an attacker can't get past. This
phase points [mcpnuke](https://github.com/babywyrm/mcpnuke) (MCP red-team scanner)
at the **same camazotz target two ways** and measures the difference:

- **Baseline** — directly at brain-gateway (`:30080`, no PEP)
- **Protected** — through the nullfield MCP-aware PEP (`:30090`)

```bash
mcpnuke --targets http://<node>:30080/mcp --fast --no-k8s --deterministic --json baseline.json   # direct
mcpnuke --targets http://<node>:30090/mcp --fast --no-k8s --deterministic --json protected.json  # via nullfield
```

## The result (verified end-to-end)

### Baseline — direct to brain-gateway (no control plane)

```
Tools 5 · Findings 27 · CRITICAL 18 · HIGH 9 · score 243
Attack chains EXECUTABLE:
  prompt_injection → code_execution     (hallucination.execute_plan, shellwrap.exec)
  prompt_injection → token_theft        (sdk.write_cache)
  code_execution   → token_theft        (… , shellwrap.exec)
  code_execution   → remote_access      (… , shellwrap.exec)
finding: "anon_budget_exhaustion: 25 unauthenticated calls succeeded"
```

The exploit invocations **succeed** — the LLM guardrail doesn't stop them
(camazotz's whole thesis), and there's nothing else in the path.

### Protected — through nullfield (same scan)

Static schema findings look similar (mcpnuke reads `tools/list`, which passes
through, so it still *sees* the dangerous tools). **What changes is runtime
enforcement** — nullfield's audit during the scan:

```
285  tool.denied      ← exploit invocations BLOCKED before reaching brain-gateway
 32  hold.created      ← high-impact calls parked for human approval
  4  tool.allowed      ← only the benign read tools were forwarded
  2  scope.modified    ← credential calls sanitized (args stripped / response redacted)
```

Of ~289 tool-call attempts the scanner threw, **4 were allowed** (the benign
reads on the allowlist); everything dangerous was denied or held. The attack
chains that are *executable* at baseline are *inert* here — the tools are
reachable in the catalog but the calls never run.

> **Read the right metric.** A scanner's finding count reflects the attack
> *surface it can see* (the schema), not the surface it can *reach*. The control
> plane's value is the **deny/allow ratio at runtime** (285:4), not a smaller
> report. Pair this with the OPA waypoint (Phase A) and the AI-egress gateway
> (Phase D) and the reachable surface collapses to the explicitly-granted set.

## Reproduce

`./mcpnuke-validate.sh` runs both scans and prints nullfield's decision counts
for the protected run (the authoritative before/after signal).

## Feedback loop (optional)

mcpnuke can turn findings into a starter nullfield policy
(`--generate-policy policy.yaml`) — scan → generate → apply → re-scan — so the
allowlist is derived from observed attack surface rather than written by hand.
