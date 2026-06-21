# Example: Zero-Trust overlay in front of a real MCP target (camazotz)

This wires the [camazotz](https://github.com/babywyrm/camazotz) MCP Security
Playground — a real, LLM-backed MCP server with **138 tools across 52 OWASP
MCP Top 10 labs** — behind the blueprint's **ambient waypoint + shared OPA PDP**.

It demonstrates the core thesis end-to-end against a *real* target:

> camazotz's whole point is that **the LLM guardrail is not a security control** —
> the model may refuse in its reasoning while the tool logic runs the dangerous
> action anyway. The zero-trust control plane sits **out of band** at the MCP
> transport, so a `tools/call` to a credential-read / RCE-ish tool is **denied
> deterministically before brain-gateway (or the LLM) ever runs.**

## What it proves (verified)

```
[PASS] initialize                   anyone       -> 200   (handshake)
[PASS] tools/list                   anyone       -> 200   (enumerate)
[PASS] chain.get_service_manifest   ci-deployer  -> 200   (granted)
[PASS] code_review.run_checks       ci-deployer  -> 200   (granted)
[PASS] cred_broker.read_credential  ci-deployer  -> 403   (DENY — not granted)
[PASS] schema.extract_credentials   support-bot  -> 403   (DENY)
[PASS] audit.list_actions           support-bot  -> 200   (granted)
[PASS] config.update_system_prompt  attacker     -> 403   (DENY — prompt-rewrite)
[PASS] exec.run_query               attacker     -> 403   (DENY)
[PASS] cred_broker.read_credential  unknown      -> 403   (DENY)
```

Bypass contrast: the same `cred_broker.read_credential` reaches and **runs** the
tool when the gate is skipped (NodePort / pod-IP) → `200`; through the waypoint
it is `403` before the workload is touched.

## Files

| File | Role |
|------|------|
| `authz-camazotz.rego` | OPA PDP corpus mapped to camazotz's real tool names (deny-by-default) |
| `mesh.yaml` | Waypoint (`waypoint-for: all`) + `CUSTOM` AuthorizationPolicy → shared `opa-ext-authz` |
| `run.sh` | Orchestrator: deploy target + load policy + enroll mesh (parameterized) |
| `verify.sh` | Portable authz matrix (pure kubectl + in-mesh curl) |

## Run it (any cluster)

```bash
# 0) base ambient control plane must exist first:
../../deploy.sh ambient

# 1) deploy camazotz behind the overlay (vars override per-cluster)
CAMAZOTZ_DIR=/opt/camazotz LLM_ENDPOINT=http://<model>:11434 LLM_MODEL=qwen3:4b ./run.sh

# 2) verify
NS=camazotz ./verify.sh
```

## Phase E — nullfield (the MCP-aware PEP)

OPA at the waypoint decides allow/deny per principal+tool. nullfield runs as a
**sidecar** in front of brain-gateway and adds the three actions OPA structurally
can't — because they require understanding and acting on the MCP call itself:

```
client → [waypoint + OPA] → nullfield :9090 → brain-gateway :8080
```

| Action | Demo tool | Result (verified) |
|--------|-----------|-------------------|
| ALLOW  | `chain.get_service_manifest` | forwarded (`tool.allowed`) |
| DENY   | `egress.fetch_url` | `-32000 denied by policy` (never reaches upstream) |
| SCOPE  | `cred_broker.read_credential` | `scope.modified` — secret args stripped, secret-shaped response values redacted |
| HOLD   | `config.update_system_prompt` | `hold.created` → parked for human approval → `tool.denied (timeout)`; approve via `POST :31591/admin/holds/<id>/approve` |
| BUDGET | `cost.invoke_llm`, `rag.query` | per-identity quota (`maxCallsPerHour`), `onExhausted: DENY` |

Deploy + verify:

```bash
# nullfield image must be in the cluster (build from github.com/babywyrm/nullfield):
#   docker build -t nullfield:local -f Dockerfile . && docker save nullfield:local | <k3s ctr|ECR push>
NS=camazotz ./nullfield-deploy.sh
NS=camazotz ./nullfield-verify.sh
```

Files: `nullfield-policy.yaml` (5-action policy mapped to camazotz tools),
`nullfield-sidecar.yaml` (config + policed Service), `nullfield-deploy.sh`,
`nullfield-verify.sh`. On EKS, build+push the image to ECR and set `IMAGE=`.

## Portability notes (k3s ↔ EKS ↔ anywhere)

Nothing here is host-specific; the per-cluster knobs are all variables:

- **Image** — `camazotz/brain-gateway` is a local build. On k3s, build + `k3s ctr
  images import`. On **EKS**, build + push to ECR and set the image in
  `camazotz/kube/brain-gateway.yaml` (or Helm values) to your ECR ref.
- **LLM endpoint** — `LLM_ENDPOINT` points camazotz's brain at any
  OpenAI/Ollama-compatible URL: a node-local Ollama (bare metal), an in-cluster
  model Service, or (Phase D) the **Envoy AI Gateway** egress broker.
- **CNI paths** — the base `deploy.sh ambient` overrides istio-cni paths for k3s
  (`/var/lib/rancher/k3s/...`). On EKS/standard clusters, **drop those overrides**
  — the default `/opt/cni/bin` + `/etc/cni/net.d` are correct.
- **NetworkPolicy** — enforcement is CNI-dependent (see top-level README). EKS VPC
  CNI + the policy agent enforce it; plain flannel may not. The mesh waypoint is
  the CNI-independent guarantee.
- **Identity** — the policy keys off the `x-principal` header for now (Phase 1).
  Phase 3 swaps this for the verified SPIFFE SVID that ztunnel already mints, so
  the principal can't be spoofed by a header.

## Tear down

```bash
kubectl delete -f mesh.yaml --ignore-not-found
kubectl delete namespace camazotz --ignore-not-found
# restore the generic demo policy in the shared OPA if desired:
kubectl create configmap opa-policy -n zerotrust \
  --from-file=authz.rego=../../policy/authz.rego --dry-run=client -o yaml | kubectl apply -f -
kubectl -n zerotrust rollout restart deploy/opa-extauthz
```
