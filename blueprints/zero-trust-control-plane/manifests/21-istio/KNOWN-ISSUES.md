# Known Issues — Istio-native topology

## 1. Sidecar inbound delivery fails on hosts with broken iptables REDIRECT interception

**Symptom:** Every in-mesh call to a sidecar-injected workload returns `503`
(`URX,UF` / `delayed_connect_error: Connection refused`). The server sidecar logs
nothing for the request. A non-mesh caller is correctly refused (mTLS works), so
the *security* layer is fine — but legitimate traffic can't reach the app either.

**This is NOT:**
- ext_authz / OPA — fails identically with the `AuthorizationPolicy` removed.
- mTLS — fails identically under `PeerAuthentication: PERMISSIVE`.
- policy, endpoints, or app bind — endpoint is HEALTHY, app serves on its port,
  client originates mTLS, `istio-init` applies its rules and reports success.

**Root cause (isolated):** the host's iptables/nftables **REDIRECT interception**
breaks the sidecar→app inbound hop (15006 → workload). This has been observed on
k3s atop a **non-standard / custom host kernel** (nf_tables backend): netfilter
modules load and a *basic* host `REDIRECT` rule works, yet the per-pod inbound
interception still fails to deliver. This is a host/kernel-level incompatibility
with sidecar iptables interception, **not** a flaw in the blueprint — the
identical manifests go green on a standard-kernel cluster.

### Diagnostic trail (for reproducing the isolation)

```
# 1. mTLS / non-bypass WORKS (security layer good):
#    non-mesh client -> mcp-server  => HTTP 000 (refused)        ✓ expected
# 2. in-mesh client -> mcp-server   => HTTP 503 URX,UF           ✗ delivery broken
# 3. remove AuthorizationPolicy, retest => still 503             (not ext_authz)
# 4. PeerAuthentication PERMISSIVE, retest => still 503          (not mTLS)
# 5. istioctl proxy-config endpoint <client> => endpoint HEALTHY (not endpoints)
# 6. istio-init log => rules generated AND applied (COMMIT, no error)
# 7. client cluster has tlsMode-istio transport socket           (client mTLS ok)
# => failure is the host's inbound REDIRECT delivery, 15006 -> app
```

### Resolutions (in order of preference)

1. **Validate on a stock-kernel cluster.** Run the same manifests on `kind`/`k3d`
   on a standard Linux/macOS host, or a burner VM with a stock Ubuntu kernel. The
   blueprint is expected to go green there — this confirms the issue is host-local.
2. **Istio ambient mode.** Ambient uses a node-level ztunnel instead of per-pod
   iptables-REDIRECT sidecars, sidestepping this interception path entirely. Trade-off:
   L7 authz (ext_authz → OPA) requires a waypoint proxy; the authz wiring differs.
3. **Istio CNI plugin** with the correct k3s paths
   (`--set values.cni.cniBinDir=/var/lib/rancher/k3s/data/cni`,
   `--set values.cni.cniConfDir=/var/lib/rancher/k3s/agent/etc/cni/net.d`). Moves
   iptables setup to a node DaemonSet. (istio-cni paths vary by distro; validate
   against a stock-kernel baseline first.)
4. **Fix the host kernel** — ensure the running kernel matches its installed
   modules (a clean reinstall of `linux-modules-extra-$(uname -r)` or a stock
   kernel), then re-test sidecar interception.

## What IS proven

- Istio control plane installs and runs.
- Sidecar injection succeeds.
- `PeerAuthentication: STRICT` makes the workload **non-bypassable** — non-mesh /
  plaintext callers are refused. This is the core zero-trust property, and the gap
  the standalone-NetworkPolicy variant cannot guarantee on a non-enforcing CNI.
- The OPA ext_authz wiring is configured correctly end to end: extensionProvider
  in meshConfig, healthy OPA PDP endpoint, `AuthorizationPolicy action: CUSTOM`,
  and the OPA **deny** decision is enforced through the mesh.

The one conditional piece is the legitimate in-mesh data path to the workload,
which depends on the host's inbound interception working (see above) — proven on a
standard-kernel cluster.
