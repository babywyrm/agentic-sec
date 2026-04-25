# Teleport Integration for Camazotz

Teleport provides machine identity and zero-trust access for agents interacting
with the camazotz MCP server. Agents authenticate via short-lived X.509
certificates instead of static API keys or long-lived tokens.

This guide walks through the complete setup on a self-hosted K8s/K3s cluster
with no external domain. Everything runs on your local network.

---

## Prerequisites

- A running K8s or K3s cluster
- `helm` v3.4+
- `kubectl` with cluster-admin access
- Camazotz deployed (brain-gateway running)
- The cluster node IP (this guide uses `192.168.1.85`)

---

## Step 1: Install Teleport Auth + Proxy

```bash
# Add Teleport Helm repo
helm repo add teleport https://charts.releases.teleport.dev
helm repo update

# Create namespace
kubectl create namespace teleport
kubectl label namespace teleport pod-security.kubernetes.io/enforce=baseline

# Write values file
cat > teleport-values.yaml << 'EOF'
clusterName: teleport.local
proxyListenerMode: multiplex
acme: false
extraArgs: ["--insecure"]

proxy:
  service:
    type: NodePort

resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: "1"
    memory: 512Mi

persistence:
  enabled: true
  storageClassName: local-path
  volumeSize: 2Gi

kubeClusterName: my-cluster
EOF

# Install
helm install teleport-cluster teleport/teleport-cluster \
  --namespace teleport \
  --values teleport-values.yaml

# Wait for pods
kubectl -n teleport rollout status deploy/teleport-cluster-auth --timeout=120s
kubectl -n teleport rollout status deploy/teleport-cluster-proxy --timeout=120s
```

Verify:

```bash
NODEPORT=$(kubectl -n teleport get svc teleport-cluster -o jsonpath="{.spec.ports[0].nodePort}")
curl -sk https://<NODE_IP>:$NODEPORT/webapi/ping | python3 -m json.tool
```

You should see `server_version` and `cluster_name: teleport.local`.

---

## Step 2: Make `teleport.local` Resolvable

The proxy generates a self-signed TLS certificate with `teleport.local` as a
SAN. Both in-cluster pods and external clients need to resolve this hostname.

### Inside the cluster (CoreDNS)

Get the proxy service ClusterIP:

```bash
PROXY_IP=$(kubectl -n teleport get svc teleport-cluster -o jsonpath="{.spec.clusterIP}")
echo "Proxy ClusterIP: $PROXY_IP"
```

Patch CoreDNS to add a hosts entry. This adds `teleport.local` to the existing
hosts block in the Corefile:

```bash
kubectl -n kube-system patch configmap coredns --type merge -p \
  "{\"data\":{\"Corefile\":\".:53 {\\n    errors\\n    health\\n    ready\\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\\n      pods insecure\\n      fallthrough in-addr.arpa ip6.arpa\\n    }\\n    hosts /etc/coredns/NodeHosts {\\n      $PROXY_IP teleport.local\\n      ttl 60\\n      reload 15s\\n      fallthrough\\n    }\\n    prometheus :9153\\n    cache 30\\n    loop\\n    reload\\n    loadbalance\\n    import /etc/coredns/custom/*.override\\n    forward . /etc/resolv.conf\\n}\\nimport /etc/coredns/custom/*.server\\n\"}}"

kubectl -n kube-system rollout restart deploy/coredns
```

Verify:

```bash
kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup teleport.local
# Should resolve to the proxy ClusterIP
```

### On the cluster node (for `tsh` and `kubectl` access)

```bash
echo "<NODE_IP> teleport.local" >> /etc/hosts
```

### On your workstation (for `tsh` access from your laptop)

```bash
# macOS/Linux
echo "<NODE_IP> teleport.local" | sudo tee -a /etc/hosts

# Windows (run as admin)
echo <NODE_IP> teleport.local >> C:\Windows\System32\drivers\etc\hosts
```

Replace `<NODE_IP>` with your cluster node's IP address.

---

## Step 3: Create an Admin User

```bash
kubectl -n teleport exec deploy/teleport-cluster-auth -- \
  tctl users add admin --roles=editor,access --logins=root
```

This prints a signup URL. Replace `teleport.local:443` in the URL with
`<NODE_IP>:<NODEPORT>` and open it in a browser to set your password.

---

## Step 4: Create Agent Roles

### Readonly K8s access

```bash
cat << 'EOF' | kubectl -n teleport exec -i deploy/teleport-cluster-auth -- tctl create -f
kind: role
version: v7
metadata:
  name: agent-readonly
spec:
  allow:
    kubernetes_groups: ["view"]
    kubernetes_labels:
      "*": "*"
    kubernetes_resources:
      - kind: pod
        namespace: "*"
        name: "*"
        verbs: ["get", "list", "watch"]
      - kind: service
        namespace: "*"
        name: "*"
        verbs: ["get", "list"]
      - kind: configmap
        namespace: "*"
        name: "*"
        verbs: ["get", "list"]
      - kind: namespace
        name: "*"
        verbs: ["get", "list"]
EOF
```

### MCP tool access

```bash
cat << 'EOF' | kubectl -n teleport exec -i deploy/teleport-cluster-auth -- tctl create -f
kind: role
version: v7
metadata:
  name: agent-mcp
spec:
  allow:
    app_labels:
      type: mcp
    mcp:
      tools:
        - "cost.*"
        - "audit.*"
        - "attribution.*"
        - "identity.*"
EOF
```

### K8s RBAC binding

The `agent-readonly` role maps to the K8s `view` group. Create the binding:

```bash
kubectl create clusterrolebinding teleport-agent-view \
  --clusterrole=view \
  --group=view
```

---

## Step 5: Create a Bot and Deploy tbot

### Create the bot

```bash
kubectl -n teleport exec deploy/teleport-cluster-auth -- \
  tctl bots add agent-bot --roles=agent-readonly,agent-mcp
```

### Create a Kubernetes join token

```bash
cat << 'EOF' | kubectl -n teleport exec -i deploy/teleport-cluster-auth -- tctl create -f
kind: token
version: v2
metadata:
  name: agent-bot-token
  expires: "2050-01-01T00:00:00Z"
spec:
  roles: [Bot]
  bot_name: agent-bot
  join_method: kubernetes
  kubernetes:
    type: in_cluster
    allow:
      - service_account: "teleport:tbot-agent"
EOF
```

### Deploy tbot via Helm

```bash
cat > tbot-values.yaml << 'EOF'
tbotConfig:
  version: v2
  auth_server: teleport-cluster-auth.teleport.svc.cluster.local:3025
  onboarding:
    join_method: kubernetes
    token: agent-bot-token
  storage:
    type: kubernetes_secret
    name: tbot
  outputs:
    - type: identity
      destination:
        type: kubernetes_secret
        name: tbot-out
    - type: kubernetes/v2
      selectors:
        - name: my-cluster   # must match kubeClusterName from Step 1
      destination:
        type: kubernetes_secret
        name: tbot-kube

extraArgs: ["--insecure"]

serviceAccount:
  create: true
  name: tbot-agent

persistence: secret
EOF

helm install tbot teleport/tbot \
  --namespace teleport \
  --values tbot-values.yaml
```

### Verify

```bash
# tbot should be 1/1 Running
kubectl -n teleport get pods -l app.kubernetes.io/name=tbot

# The kubeconfig secret should exist with real keys
kubectl -n teleport get secret tbot-kube -o jsonpath="{.data}" | \
  python3 -c "import sys,json; print('\n'.join(sorted(json.load(sys.stdin).keys())))"
# Expected: .write-test, identity, key, key-cert.pub, key.pub, kubeconfig.yaml, ...
```

### Test K8s access

```bash
NODEPORT=$(kubectl -n teleport get svc teleport-cluster -o jsonpath="{.spec.ports[0].nodePort}")

kubectl -n teleport get secret tbot-kube -o jsonpath="{.data.kubeconfig\.yaml}" | \
  base64 -d | sed "s|teleport.local:443|<NODE_IP>:$NODEPORT|g" > /tmp/tbot-kubeconfig.yaml

KUBECONFIG=/tmp/tbot-kubeconfig.yaml kubectl --insecure-skip-tls-verify get pods -A
```

You should see all pods in the cluster, accessed via the bot's short-lived cert.

---

## Step 6: Deploy MCP App Access Agent

### Create the app join token

```bash
cat << 'EOF' | kubectl -n teleport exec -i deploy/teleport-cluster-auth -- tctl create -f
kind: token
version: v2
metadata:
  name: app-agent-token
  expires: "2050-01-01T00:00:00Z"
spec:
  roles: [App]
  join_method: kubernetes
  kubernetes:
    type: in_cluster
    allow:
      - service_account: "teleport:teleport-app-agent"
EOF
```

### Extract the proxy cert for trust

The app agent needs to trust the proxy's self-signed TLS cert. Extract it:

```bash
PROXY_IP=$(kubectl -n teleport get svc teleport-cluster -o jsonpath="{.spec.clusterIP}")

echo | openssl s_client -connect $PROXY_IP:443 -servername teleport.local 2>/dev/null \
  | openssl x509 > proxy-cert.pem

kubectl -n teleport create configmap teleport-proxy-ca \
  --from-file=ca.crt=proxy-cert.pem
```

**Important:** If the proxy pod restarts, it generates a new cert. You must
re-extract and update the configmap. To avoid this, use cert-manager to issue
a stable cert (see Limitations below).

### Deploy the app agent

```bash
cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: teleport-app-agent
  namespace: teleport
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: teleport-app-agent-config
  namespace: teleport
data:
  teleport.yaml: |
    version: v3
    teleport:
      proxy_server: teleport.local:443
      data_dir: /var/lib/teleport
      join_params:
        method: kubernetes
        token_name: app-agent-token
    auth_service:
      enabled: false
    proxy_service:
      enabled: false
    ssh_service:
      enabled: false
    app_service:
      enabled: true
      apps:
        - name: camazotz-mcp
          uri: http://brain-gateway.camazotz.svc.cluster.local:8080
          labels:
            type: mcp
            environment: lab
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: teleport-app-agent
  namespace: teleport
spec:
  replicas: 1
  selector:
    matchLabels:
      app: teleport-app-agent
  template:
    metadata:
      labels:
        app: teleport-app-agent
    spec:
      serviceAccountName: teleport-app-agent
      containers:
        - name: teleport
          image: public.ecr.aws/gravitational/teleport-distroless:18.7.5
          args: ["-c", "/etc/teleport/teleport.yaml"]
          env:
            - name: SSL_CERT_FILE
              value: /etc/teleport-ca/ca.crt
          volumeMounts:
            - name: config
              mountPath: /etc/teleport
              readOnly: true
            - name: proxy-ca
              mountPath: /etc/teleport-ca
              readOnly: true
            - name: data
              mountPath: /var/lib/teleport
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
      volumes:
        - name: config
          configMap:
            name: teleport-app-agent-config
        - name: proxy-ca
          configMap:
            name: teleport-proxy-ca
        - name: data
          emptyDir: {}
EOF
```

### Verify

```bash
# App agent should be 1/1 Running
kubectl -n teleport get pods -l app=teleport-app-agent

# The MCP app should be registered in Teleport
kubectl -n teleport exec deploy/teleport-cluster-auth -- tctl get app
# Should show: camazotz-mcp with uri: http://brain-gateway...
```

---

## Architecture Summary

```text
┌─────────────────────────────────────────────────────────────────────┐
│  K8s Cluster                                                        │
│                                                                     │
│  teleport namespace                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────┐  ┌─────────────┐ │
│  │ Auth Service  │  │ Proxy Service│  │  tbot   │  │  App Agent  │ │
│  │              │◄─┤  :443 (TLS)  │  │         │  │             │ │
│  │ issues certs │  │  NodePort    │  │ produces│  │ proxies MCP │ │
│  │ manages roles│  │  30136       │  │ kubeconf│  │ camazotz-mcp│ │
│  └──────┬───────┘  └──────┬───────┘  └────┬────┘  └──────┬──────┘ │
│         │                 │               │               │        │
│         │    gRPC :3025   │  teleport.local resolves      │        │
│         │◄────────────────┘  via CoreDNS to proxy ClusterIP        │
│         │                                                 │        │
│  camazotz namespace                                       │        │
│  ┌─────────────────────────────────────┐                  │        │
│  │ brain-gateway + nullfield sidecar   │◄─────────────────┘        │
│  │ :8080 (MCP)    :9090 (proxy)        │                           │
│  └─────────────────────────────────────┘                           │
│                                                                     │
│  DNS: teleport.local → proxy ClusterIP (CoreDNS)                   │
│  DNS: teleport.local → <NODE_IP> (/etc/hosts on host + clients)    │
└─────────────────────────────────────────────────────────────────────┘

Agent authentication flow:

  1. tbot authenticates to Auth via K8s ServiceAccount JWT
  2. Auth issues short-lived X.509 cert (1h TTL, auto-renewed)
  3. tbot writes kubeconfig to K8s Secret (tbot-kube)
  4. Any pod mounting tbot-kube gets authenticated K8s access
  5. App Agent registers camazotz-mcp through proxy tunnel
  6. Agents with agent-mcp role can reach MCP tools through Teleport
```

---

## Testing with mcpnuke

mcpnuke includes Teleport-aware security checks. Run against brain-gateway
using the node IP so the Teleport checks probe the right host:

```bash
# Fast scan (no tool invocation) — includes Teleport infrastructure checks
mcpnuke --targets http://<NODE_IP>:30080/mcp --fast --no-invoke --verbose

# Full scan with Teleport lab exploit chains (invokes tools)
mcpnuke --targets http://localhost:8080/mcp --verbose
```

### Infrastructure checks (always run)

| Check | What it does |
|---|---|
| `teleport_proxy_discovery` | Finds proxy via `/webapi/ping`, reports version and auth config |
| `teleport_cert_validation` | Flags self-signed proxy certs (MITM risk in production) |
| `teleport_app_enumeration` | Tests if app list is exposed to unauthenticated callers |
| `tbot_credential_exposure` | Checks if tbot secrets are readable by non-tbot pods |
| `teleport_bot_overprivilege` | Flags bot SAs bound to cluster-admin or edit roles |

### Exploit chain checks (require `--invoke`, skip with `--no-invoke`)

| Check | Attack chain | Threat |
|---|---|---|
| `teleport_lab_bot_theft` | Read tbot secret → replay identity → check session binding | MCP-T04 |
| `teleport_lab_role_escalation` | Get roles → request escalation → privileged operation | MCP-T20 |
| `teleport_lab_cert_replay` | Get expired cert → replay → check replay detection | MCP-T26 |

---

## Teleport Roles Reference

| Role | Purpose | K8s groups | App labels | MCP tools |
|---|---|---|---|---|
| `agent-readonly` | K8s read access for agents | `view` | — | — |
| `agent-ops` | K8s write access (camazotz namespace) | `edit` | — | — |
| `agent-mcp` | MCP tool access via App Access | — | `type: mcp` | `cost.*`, `audit.*`, `attribution.*`, `identity.*` |

---

## Limitations

- **Self-signed cert rotation:** The proxy cert changes on pod restart. The
  `teleport-proxy-ca` configmap must be updated (re-extract + recreate). Use
  cert-manager with a stable issuer to avoid this.
- **No access requests:** Teleport Community Edition does not support
  just-in-time access requests. Role assignments are static. Enterprise
  adds approval workflows.
- **External client access:** `tsh` on your workstation requires
  `teleport.local` in `/etc/hosts` pointing to the node IP, plus
  `--insecure` flag for self-signed certs:
  ```bash
  tsh login --proxy=teleport.local:<NODEPORT> --insecure --user=admin
  tsh kube login my-cluster
  ```
- **No ACME/Let's Encrypt:** Without a real domain, automatic cert provisioning
  is not available. The self-signed cert + `/etc/hosts` approach works for lab
  and development environments.
