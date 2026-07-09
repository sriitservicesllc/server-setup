# 🚀 Production Kubernetes Platform — Ansible Deployment

> **Small Product Development Company Stack** | 1 Master + 3 Workers (configurable) | Bare-metal | 28-step automated setup | **100% Open Source**

---

## ✅ Open Source License Audit

Every component in this stack is verified open source. No enterprise licenses, no trial keys, no phone-home required.

| Component | License | Notes |
|-----------|---------|-------|
| **Kubernetes** | Apache 2.0 | |
| **containerd** | Apache 2.0 | |
| **Calico CNI** | Apache 2.0 | |
| **MetalLB** | Apache 2.0 | |
| **NGINX Ingress** | Apache 2.0 | |
| **cert-manager** | Apache 2.0 | |
| **Longhorn** | Apache 2.0 | |
| **MinIO** | AGPL-3.0 | Free self-hosted use |
| **Kong Gateway OSS** | Apache 2.0 | `image: kong:3.7` + `enterprise.enabled: false` |
| **Kong Manager OSS** | Apache 2.0 | Bundled with Kong ≥3.4, no license key |
| **Harbor** | Apache 2.0 | |
| **Trivy Operator** | Apache 2.0 | |
| **Gitea** | MIT | Email-based auth, no SSO dependency |
| **Woodpecker CI** | Apache 2.0 | |
| **ArgoCD** | Apache 2.0 | |
| **SonarQube Community** | LGPLv3 (core) | Analyzers: SSALv1 (free self-hosted) |
| **OpenBao** | MPL-2.0 | Linux Foundation fork of Vault — replaces HashiCorp Vault (BSL 1.1 ❌) |
| **PostgreSQL** | PostgreSQL License | |
| **MySQL** | GPL-2.0 | |
| **Redis** | BSD-3-Clause (≤7.2) | Bitnami chart uses Redis 7.x |
| **RabbitMQ** | MPL-2.0 | Direct StatefulSet with the official RabbitMQ image |
| **Elasticsearch** | ELv2 | Free self-hosted; not Apache but free-to-use |
| **Kibana** | ELv2 | Same as above |
| **Fluent Bit** | Apache 2.0 | |
| **Prometheus** | Apache 2.0 | |
| **Grafana** | AGPL-3.0 | |
| **Alertmanager** | Apache 2.0 | |
| **Wiki.js** | AGPL-3.0 | |
| **Mattermost Team Ed.** | MIT | |
| **Velero** | Apache 2.0 | |
| **rclone** | MIT | |
| **Helm** | Apache 2.0 | |

> **Why OpenBao instead of HashiCorp Vault?**
> In August 2023 HashiCorp changed Vault's license from MPL-2.0 to **BSL 1.1**, which is not an OSI-approved open-source license. **OpenBao** (governed by the Linux Foundation) is the community MPL-2.0 fork with a 100% compatible API. All Vault usage examples and annotations work unchanged.

---

## Platform Architecture

```
                          ╔══════════════════════════════╗
                          ║       INTERNET / LAN         ║
                          ╚══════════════╦═══════════════╝
                                         │
                           ╔═════════════▼══════════════╗
                           ║   MetalLB Load Balancer    ║
                           ║   IPs: 192.168.1.200–220   ║
                           ╚═════════════╦══════════════╝
                                         │
                           ╔═════════════▼══════════════╗
                           ║   NGINX Ingress Controller  ║
                           ║   (TLS termination, routing)║
                           ╚══╦══════════╦══════════════╝
                              │          │
              ╔═══════════════▼╗    ╔════▼═══════════════╗
              ║  Kong API GW   ║    ║  Platform UIs       ║
              ║  api.*         ║    ║  git.* ci.* argocd.*║
              ║  Rate limit    ║    ║  grafana.* wiki.*   ║
              ║  JWT auth      ║    ║  sonar.* chat.*     ║
              ║  CORS / Cache  ║    ╚═════════════════════╝
              ╚════════════════╝
                       │
       ╔═══════════════▼══════════════════════════════════╗
       ║               KUBERNETES CLUSTER                 ║
       ║                                                  ║
       ║  ┌─────────────┐  ┌──────────┐  ┌──────────┐   ║
       ║  │  master-01  │  │worker-01 │  │worker-02 │   ║
       ║  │ (Control    │  │(general) │  │(general) │   ║
       ║  │  Plane)     │  │          │  │          │   ║
       ║  └─────────────┘  └──────────┘  └──────────┘   ║
       ║                                  ┌──────────┐   ║
       ║                                  │worker-03 │   ║
       ║                                  │(storage) │   ║
       ║                                  └──────────┘   ║
       ╚══════════════════════════════════════════════════╝
```

### Developer GitOps Workflow

```
 Developer
     │
     │  git push
     ▼
 ┌─────────┐  webhook  ┌─────────────────┐  push image  ┌──────────┐
 │  Gitea  │──────────►│  Woodpecker CI  │─────────────►│  Harbor  │
 │  (Git)  │           │  • test         │              │(Registry)│
 └─────────┘           │  • sonar-scan   │              └──────────┘
                        │  • build image  │
                        │  • update tag   │
                        └────────┬────────┘
                                 │ commits manifest
                                 ▼
                         ┌──────────────┐
                         │  Gitea Repo  │  ArgoCD watches
                         │  (manifests) │──────────────────►  K8s Cluster
                         └──────────────┘  auto-sync
```

---

## Complete Component List (28 Deployment Steps)

### 🏗 Layer 1 — Cluster Foundation (Steps 1–8)

| Step | Component | Notes |
|------|-----------|-------|
| 01 | **Preflight Checks** | RAM ≥4GB, CPU ≥2, Ubuntu 22.04, disk ≥50GB |
| 02 | **Common OS Setup** | Swap off, sysctl, kernel modules, NTP |
| 03 | **containerd** | Container runtime with SystemdCgroup |
| 04 | **kubeadm + kubelet + kubectl + Helm** | Kubernetes 1.29 + all Helm chart repos |
| 05 | **Control Plane Init** | kubeadm with audit logs, RBAC, IPVS mode |
| 06 | **Calico CNI** | Pod networking with VXLAN cross-subnet |
| 07 | **Worker Join** | All workers auto-join via token |
| 08 | **Node Labels & Taints** | `workload=general`, `workload=storage` |

### 🌐 Layer 2 — Networking (Steps 9–11)

| Step | Component | URL | Notes |
|------|-----------|-----|-------|
| 09 | **MetalLB** | — | Assigns `192.168.1.200–220` to LoadBalancer services |
| 10 | **NGINX Ingress** | — | HTTP/HTTPS routing, autoscaling 2–10 replicas, Prometheus metrics |
| 11 | **cert-manager** | — | Let's Encrypt (staging + prod) + self-signed for internal services |

### 💾 Layer 3 — Storage (Steps 12–13)

| Step | Component | URL | Notes |
|------|-----------|-----|-------|
| 12 | **Longhorn** | `longhorn.sriitservices.local` | Replicated block storage, 3 StorageClasses |
| 13 | **MinIO** | `minio-console.sriitservices.local` | S3-compatible object store; Velero backup target |

> **StorageClasses available:**
> - `longhorn` — default, 2 replicas
> - `longhorn-fast` — SSD-targeted (for databases)
> - `longhorn-backup` — single replica (logs/backups)

### 🔀 Layer 4 — API Gateway (Step 14)

| Step | Component | URL | Notes |
|------|-----------|-----|-------|
| 14 | **Kong Gateway OSS** | `api.sriitservices.local` | Apache 2.0 · `image: kong:3.7` · `enterprise.enabled: false` |
| — | Kong Manager OSS | `kong-manager.sriitservices.local` | Visual route & plugin management (free since Kong 3.4, no license key) |
| — | Kong Admin API | `kong-admin.sriitservices.local` | REST API for config (restricted to internal CIDR) |

**Default Kong plugins (globally active):**
- `rate-limiting` — 1000 req/min per IP
- `cors` — configurable origins
- `bot-detection` — blocks known crawlers
- `proxy-cache` — 300s cache for GET/HEAD
- `jwt` — per-route JWT auth (opt-in via annotation)
- `key-auth` — API key auth (opt-in)
- `ip-restriction` — CIDR allowlist (opt-in)

### 📦 Layer 5 — Registry & Security (Steps 15–16)

| Step | Component | URL | Notes |
|------|-----------|-----|-------|
| 15 | **Harbor** | `registry.sriitservices.local` | Docker registry + Trivy scanning + Notary signing + Helm chart repo |
| 16 | **Trivy Operator** | — | Continuous cluster-wide image scanning, RBAC & config audits, CIS benchmark |

### 🔧 Layer 6 — DevOps Toolchain (Steps 17–21)

| Step | Component | URL | Auth | Notes |
|------|-----------|-----|------|-------|
| 17 | **Gitea** | `git.sriitservices.local` | **Email-based** | Git, Issues, PRs, Projects, SSH clone; direct container deployment |
| 18 | **Woodpecker CI** | `ci.sriitservices.local` | Gitea OAuth2 | Container-native pipelines, K8s agent backend |
| 19 | **ArgoCD** | `argocd.sriitservices.local` | Local admin | GitOps CD, AppProjects for prod/staging |
| 20 | **SonarQube** | `sonar.sriitservices.local` | Local admin | Code quality, security hotspots, coverage |
| 21 | **OpenBao** | `vault.sriitservices.local` | Unseal keys | Secrets mgmt, pod sidecar injection (MPL-2.0, Linux Foundation) |

### 🗄 Layer 7 — Databases (Step 22)

| Component | Internal Endpoint | Notes |
|-----------|-------------------|-------|
| **PostgreSQL** | `postgresql.databases.svc.cluster.local:5432` | HA with 2 read replicas, `pg_stat_statements`, `uuid-ossp` |
| **MySQL** | `mysql.databases.svc.cluster.local:3306` | Primary + 1 secondary |
| **Redis** | `redis-master.databases.svc.cluster.local:6379` | Sentinel HA mode, 2 replicas |
| **RabbitMQ** | `rabbitmq.databases.svc.cluster.local:5672` | AMQP broker with persistent volume and Prometheus metrics |

### 📋 Layer 8 — Logging (Step 23)

| Component | URL | Notes |
|-----------|-----|-------|
| **Elasticsearch** | (internal) | ECK operator, configurable replicas |
| **Kibana** | `kibana.sriitservices.local` | Log dashboards, alerting |
| **Fluent Bit** | (DaemonSet) | Collects all container logs, ships to Elasticsearch |

### 📊 Layer 9 — Monitoring (Step 24)

| Component | URL | Notes |
|-----------|-----|-------|
| **Prometheus** | `prometheus.sriitservices.local` | 30d retention, 30s scrape interval |
| **Grafana** | `grafana.sriitservices.local` | 12 dashboards pre-loaded (K8s, Nodes, NGINX, Longhorn, DBs, Kong) |
| **Alertmanager** | `alertmanager.sriitservices.local` | Custom rules: CPU, memory, disk, pod crashes, DB down |

**Pre-loaded Grafana dashboards:** Kubernetes Cluster, Node Exporter, NGINX Ingress, Longhorn, PostgreSQL, Redis, Kong

### 🤝 Layer 10 — Collaboration (Steps 25–26)

| Step | Component | URL | Notes |
|------|-----------|-----|-------|
| 25 | **Wiki.js** | `wiki.sriitservices.local` | Markdown wiki, optional Git storage backend via Gitea |
| 26 | **Mattermost** | `chat.sriitservices.local` | Team chat, Gitea/ArgoCD/Grafana bot integrations |

### 💾 Layer 11 — Backup (Step 27)

| Component | Notes |
|-----------|-------|
| **Velero** | Daily (7d) + weekly (30d) cluster backups → MinIO |
| **rclone CronJob** | Nightly MinIO → OneDrive sync (3-2-1 backup strategy) |

---

## Quick Start

### Prerequisites

**Ansible control machine** (your laptop or CI server):
```bash
pip install ansible ansible-core
ansible-galaxy collection install -r requirements.yml
```

**Each node** must have:
| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 2 vCPU | 4+ vCPU |
| RAM | 4 GB | 8+ GB |
| Disk | 50 GB | 100+ GB SSD |
| OS | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |

### Step 1 — Configure Your Nodes

Edit [`inventory/hosts.yml`](inventory/hosts.yml):
```yaml
k8s_masters:
  hosts:
    master-01:
      ansible_host: 192.168.1.100   # ← your master IP

k8s_workers:
  hosts:
    worker-01:
      ansible_host: 192.168.1.101
    worker-02:
      ansible_host: 192.168.1.102
    worker-03:
      ansible_host: 192.168.1.103
	worker-04:
      ansible_host: 192.168.1.104
```

**To add/remove workers:** just add/remove entries from `k8s_workers`. No code changes required.

### Step 2 — Configure Variables

Edit [`inventory/group_vars/all.yml`](inventory/group_vars/all.yml) for the key settings:

```yaml
# Your LAN IP range for LoadBalancer services
metallb_ip_range: "192.168.1.200-192.168.1.220"

# Base domain for all internal services
harbor_hostname: "registry.sriitservices.local"
gitea_hostname:  "git.sriitservices.local"
# ... (all other hostnames follow the same pattern)

# Enable SMTP for Gitea email registration (optional)
gitea_smtp_enabled: true
gitea_smtp_host: "smtp.gmail.com"
gitea_smtp_user: "your@gmail.com"

# Kong API proxy hostname
kong_proxy_hostname: "api.sriitservices.local"
```

### Step 3 — Set Up Secrets (Ansible Vault)

```bash
# Copy the template
cp inventory/group_vars/vault.yml.template inventory/group_vars/vault.yml

# Edit all CHANGE_ME values with real passwords
nano inventory/group_vars/vault.yml

# Encrypt it
ansible-vault encrypt inventory/group_vars/vault.yml
```

### Step 4 — Set Up SSH Keys

```bash
# Generate a dedicated cluster key
ssh-keygen -t ed25519 -f ~/.ssh/k8s_cluster_key -C "k8s-ansible"

# Prerequisite: the `ansible` user must already exist on each server
# (or update `inventory/hosts.yml` to match a pre-existing sudo-capable user)

# Copy to all nodes
 for ip in 192.168.1.100 192.168.1.101 192.168.1.102 192.168.1.103  192.168.1.104; do
      ssh-copy-id -o StrictHostKeyChecking=accept-new -i ~/.ssh/k8s_cluster_key.pub ansible@$ip
    done

# Test connectivity
ansible k8s_cluster -m ping
```

### Step 5 — Deploy

```bash
# Full deployment (~45-90 min depending on hardware)
ansible-playbook site.yml --ask-vault-pass

# With verbose output
ansible-playbook site.yml -v --ask-vault-pass

# Dry run
ansible-playbook site.yml --check --ask-vault-pass
```

---

## Selective Deployment (Tags)

Run only specific components without re-running everything:

```bash
# Bootstrap (OS + binaries only)
ansible-playbook site.yml --tags bootstrap --ask-vault-pass

# Networking
ansible-playbook site.yml --tags "metallb,ingress,networking" --ask-vault-pass

# Kong API Gateway only
ansible-playbook site.yml --tags kong --ask-vault-pass

# DevOps toolchain
ansible-playbook site.yml --tags "gitea,woodpecker,argocd,sonarqube" --ask-vault-pass

# Databases only
ansible-playbook site.yml --tags databases --ask-vault-pass

# Monitoring only
ansible-playbook site.yml --tags monitoring --ask-vault-pass

# Logging only
ansible-playbook site.yml --tags logging --ask-vault-pass

# Backup (Velero + rclone OneDrive)
ansible-playbook site.yml --tags "velero,backup" --ask-vault-pass

# Validate cluster health
ansible-playbook site.yml --tags validate --ask-vault-pass
```

---

## Scaling the Cluster

### Add a new worker
```yaml
# inventory/hosts.yml
k8s_workers:
  hosts:
    worker-04:                     # ← add this
      ansible_host: 192.168.1.14
      node_labels:
        workload: general
```
```bash
ansible-playbook site.yml --tags workers --limit worker-04 --ask-vault-pass
```

### Scale Kong horizontally
```yaml
# inventory/group_vars/all.yml  (autoscaling handles this automatically)
# Or override in Helm values — see roles/kong/tasks/main.yml
```

---

## Resource Budget by Tool

The table below reflects the CPU and memory values explicitly configured in the Ansible roles. When a role does not set pod resources, I marked it as not explicitly set instead of guessing chart defaults.

| Tool | Memory (Min / Max) | CPU (Min / Max) | Notes |
|------|--------------------|-----------------|-------|
| NGINX Ingress Controller | 90Mi / 512Mi | 100m / 1000m | Autoscaled 2–10 replicas |
| cert-manager | 32Mi / 128Mi | 10m / 100m | Controller only |
| Longhorn | 256Mi / — | 250m / — | Requests only; no limits set in the role |
| Harbor | — / — | — / — | No explicit pod resources set in the repo |
| Trivy Operator | 100M / 500M | 100m / 500m | Cluster-wide scanner |
| PostgreSQL | 256Mi / 1Gi | 250m / 1000m | Primary and read replicas use the same values |
| MySQL | 256Mi / 1Gi | 250m / 1000m | Only if `mysql_enabled: true` |
| Redis | 128Mi / 512Mi | 100m / 500m | Master pod only is pinned |
| RabbitMQ | 256Mi / 1Gi | 100m / 500m | Explicit pod resources are set in the role |
| Elasticsearch | 2Gi / 4Gi | 500m / 2000m | ECK-managed data node |
| Kibana | 512Mi / 1Gi | 250m / 1000m | Web UI |
| Prometheus | 2Gi / 4Gi | 500m / 2000m | Main server pod |
| Grafana | 128Mi / 512Mi | 100m / 500m | Dashboard UI |
| Alertmanager | — / — | — / — | No explicit pod resources set in the repo |
| MinIO | 512Mi / 2Gi | 250m / 1000m | API and console live behind ingress |
| Kong Gateway OSS | 512Mi / 2Gi | 500m / 2000m | Covers proxy, admin API, and manager |
| Gitea | 256Mi / 1Gi | 200m / 1000m | Web UI plus SSH service |
| Woodpecker CI server | 128Mi / 512Mi | 100m / 500m | Web UI |
| Woodpecker CI agent | 128Mi / 1Gi | 100m / 1000m | Kubernetes backend workers |
| ArgoCD bundle | 64Mi / 1Gi | 100m / 1000m | Aggregated across server/repo-server/sidecars |
| SonarQube | 2Gi / 4Gi | 500m / 2000m | Community edition |
| OpenBao | 256Mi / 512Mi | 250m / 500m | Injector is 256Mi/256Mi; server is 256Mi/512Mi |
| Wiki.js | 256Mi / 1Gi | 100m / 500m | Web UI |
| Mattermost | 256Mi / 1Gi | 250m / 1000m | Team chat |
| Infisical | — / — | — / — | No explicit pod resources set in the repo |
| Velero | 128Mi / 512Mi | 500m / 1000m | Backup controller |

## Home Network Access

All application hostnames are meant to resolve to the NGINX Ingress LoadBalancer IP on your LAN. That means you can access the stack from any device on the home network by pointing local DNS or `/etc/hosts` at the ingress IP.

```bash
# Get the NGINX Ingress external IP
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Add the hostnames to your internal DNS server or to `/etc/hosts` on your laptop/workstation:

```text
<INGRESS_IP>  registry.sriitservices.local
<INGRESS_IP>  minio.sriitservices.local (For Apps no UI)
<INGRESS_IP>  minio-console.sriitservices.local
<INGRESS_IP>  api.sriitservices.local
<INGRESS_IP>  kong-manager.sriitservices.local
<INGRESS_IP>  kong-admin.sriitservices.local
<INGRESS_IP>  git.sriitservices.local
<INGRESS_IP>  ci.sriitservices.local (not ui)
<INGRESS_IP>  argocd.sriitservices.local
<INGRESS_IP>  sonar.sriitservices.local
<INGRESS_IP>  vault.sriitservices.local
<INGRESS_IP>  grafana.registry.sriitservices.local
<INGRESS_IP>  prometheus.registry.sriitservices.local
<INGRESS_IP>  alertmanager.registry.sriitservices.local*
<INGRESS_IP>  kibana.sriitservices.local*
<INGRESS_IP>  longhorn.sriitservices.local*
<INGRESS_IP>  wiki.sriitservices.local
<INGRESS_IP>  chat.sriitservices.local
<INGRESS_IP>  infisical.sriitservices.local*
```

If you already run a home NGINX reverse proxy, point it at the ingress IP and preserve the original host header. A minimal pattern looks like this:

```nginx
server {
  listen 443 ssl;
  server_name git.sriitservices.local;

  location / {
    proxy_pass https://<INGRESS_IP>; # replace with the IP reported by kubectl
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_ssl_server_name on;
  }
}
```

### All Service URLs

| Service | URL | Access Notes |
|---------|-----|--------------|
| Harbor Registry | https://registry.sriitservices.local | Web UI + Docker/Helm registry |
| MinIO API | https://minio.sriitservices.local | S3 endpoint |
| MinIO Console | https://minio-console.sriitservices.local | Web console |
| **Kong Proxy** | **https://api.sriitservices.local** | Public API entrypoint |
| Kong Manager | https://kong-manager.sriitservices.local | LAN-only via ingress whitelist |
| Kong Admin API | https://kong-admin.sriitservices.local | LAN-only via ingress whitelist |
| Gitea | https://git.sriitservices.local | Web UI; SSH clone uses the LoadBalancer IP on port 22 |
| Woodpecker CI | https://ci.sriitservices.local | Login with Gitea credentials |
| ArgoCD | https://argocd.sriitservices.local | GitOps UI |
| SonarQube | https://sonar.sriitservices.local | Code quality UI |
| **OpenBao** | https://vault.sriitservices.local | Manual unseal after restart |
| Grafana | https://grafana.sriitservices.local | Dashboards and alerts |
| Prometheus | https://prometheus.sriitservices.local | Metrics UI |
| Alertmanager | https://alertmanager.sriitservices.local | Alert routing UI |
| Kibana | https://kibana.sriitservices.local | Log search UI |
| Longhorn UI | https://longhorn.sriitservices.local | Storage UI; basic auth enabled |
| Wiki.js | https://wiki.sriitservices.local | Documentation UI |
| Mattermost | https://chat.sriitservices.local | Team chat |
| Infisical | https://infisical.sriitservices.local | Secret management UI |
| PostgreSQL | Internal only | `postgresql.databases.svc.cluster.local:5432` |
| MySQL | Internal only | `mysql.databases.svc.cluster.local:3306` |
| Redis | Internal only | `redis-master.databases.svc.cluster.local:6379` |
| RabbitMQ | Internal only | `rabbitmq.databases.svc.cluster.local:5672` |
| Velero | CLI only | Backups live in MinIO; use the `velero` CLI |

---

## Kong API Gateway — Usage Guide

### Register a Service & Route

```bash
KONG_ADMIN="https://kong-admin.sriitservices.local"

# 1. Register your backend service
curl -X POST $KONG_ADMIN/services \
  --data name=my-api \
  --data url=http://my-service.default.svc.cluster.local:8080

# 2. Create a route
curl -X POST $KONG_ADMIN/services/my-api/routes \
  --data 'paths[]=/api/v1/my-api' \
  --data 'strip_path=false'

# 3. Clients now reach it at:
#    https://api.sriitservices.local/api/v1/my-api
```

### Enable JWT Auth on a Route

```bash
# Enable JWT plugin on the my-api service
curl -X POST $KONG_ADMIN/services/my-api/plugins \
  --data name=jwt

# Create a consumer
curl -X POST $KONG_ADMIN/consumers --data username=my-app

# Generate a JWT credential
curl -X POST $KONG_ADMIN/consumers/my-app/jwt
```

### Enable Rate Limiting Per-Route

```bash
curl -X POST $KONG_ADMIN/services/my-api/plugins \
  --data name=rate-limiting \
  --data config.minute=100 \
  --data config.policy=local
```

### Using Kong via Kubernetes Ingress Annotation

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-api
  namespace: default
  annotations:
    kubernetes.io/ingress.class: "nginx"           # or "kong" if using KIC
    konghq.com/plugins: "jwt-auth,rate-limiting"   # apply plugins
spec:
  rules:
    - host: api.sriitservices.local
      http:
        paths:
          - path: /api/v1/my-api
            pathType: Prefix
            backend:
              service:
                name: my-api-service
                port: { number: 8080 }
```

---

## Gitea — Email-Based Authentication

Gitea is deployed directly from the official container image, backed by PostgreSQL, with **local account + email** authentication only (no external SSO).

The same role now also deploys an `act_runner` instance for Gitea Actions. It registers automatically from the shared `gitea_runner_registration_token` and talks to a local Docker daemon provided by a Docker-in-Docker (DinD) sidecar container, so workflows can run Docker-based job steps without depending on the host's Docker socket.

### User Management

| Action | How |
|--------|-----|
| Admin creates user | `git.sriitservices.local/-/admin/users/new` |
| Self-registration | Enabled by default (`gitea_allow_registration: true`) |
| Disable registration | Set `gitea_allow_registration: false` in `all.yml` + re-run Gitea role |
| Email confirmation | Set `gitea_smtp_enabled: true` + configure SMTP in `all.yml` |

### Enable SMTP Email (Optional)

```yaml
# inventory/group_vars/all.yml
gitea_smtp_enabled: true
gitea_smtp_host: "smtp.gmail.com"
gitea_smtp_port: 587
gitea_smtp_user: "your@gmail.com"
gitea_smtp_from: "gitea@sriitservices.com"

# inventory/group_vars/vault.yml  (encrypted)
gitea_smtp_password: "your-gmail-app-password"
```

Then re-apply:
```bash
ansible-playbook site.yml --tags gitea --ask-vault-pass
```

### Connect Woodpecker CI

After Gitea deploys, create an OAuth2 app:
1. Login to Gitea → **Site Administration → Applications → Add OAuth2 Application**
2. Name: `Woodpecker CI`
3. Redirect URI: `https://ci.sriitservices.local/authorize`
4. Copy the **Client ID** and **Client Secret**
5. Add to `vault.yml`:
   ```yaml
   woodpecker_gitea_client_id: "YOUR_CLIENT_ID"
   woodpecker_gitea_client_secret: "YOUR_CLIENT_SECRET"
   ```
6. Run: `ansible-playbook site.yml --tags woodpecker --ask-vault-pass`

### Configure Repositories & Secrets in Woodpecker

Once you log in to the Woodpecker dashboard (`https://ci.sriitservices.local`) with your Gitea credentials, perform the following setup steps for your repository:

#### 1. Activate Trusted Mode
The container build/push steps run as a privileged step to talk to the Docker daemon. Woodpecker requires the repo to be flagged as **Trusted** in the dashboard UI for this to execute.
* **Via Web UI:**
  1. Go to the Woodpecker dashboard.
  2. Open your repository.
  3. Navigate to **Settings** (gear icon on the top right).
  4. Toggle **Trusted** to `ON`.
  > [!NOTE]
  > Only Woodpecker server administrators (configured via `gitea_admin_user` / `WOODPECKER_ADMIN`) can activate Trusted mode.
* **Via CLI:**
  ```bash
  woodpecker-cli repo update --repository <owner/repo> --trusted
  ```

#### 2. Add Repository Secrets
Navigate to your Woodpecker repository settings and register the following credentials under the **Secrets** tab (or via Woodpecker CLI):
* **`harbor_username`**: Your Harbor username or a robot account's username.
* **`harbor_password`**: Your Harbor password or a robot account's secret token.
* **`argocd_server`**: Your ArgoCD server address.
* **`argocd_auth_token`**: Your ArgoCD local/admin authentication token.

* **Via CLI:**
  ```bash
  woodpecker-cli repo secret add --repository <owner/repo> --name harbor_username --value "<username>"
  woodpecker-cli repo secret add --repository <owner/repo> --name harbor_password --value "<password>"
  woodpecker-cli repo secret add --repository <owner/repo> --name argocd_server --value "<server_address>"
  woodpecker-cli repo secret add --repository <owner/repo> --name argocd_auth_token --value "<auth_token>"
  ```


### Gitea Actions Runner

The runner is enabled by default with these values in `inventory/group_vars/all.yml`:

- `gitea_runner_enabled`
- `gitea_runner_image`
- `gitea_runner_name`
- `gitea_runner_labels`
- `gitea_runner_registration_token`

The registration token must be retrieved from Gitea and configured in your settings. Move it to `vault.yml` before production use.

#### How to Retrieve the Token & Integrate the Runner:
1. Log in to your Gitea Web UI (e.g. `https://git.sriitservices.local`) as an administrator (`gitadmin`).
2. Navigate to **Site Administration** (wrench icon or menu in the top-right).
3. In the left panel, click on **Actions** → **Runners**.
4. Click the **Create New Runner** button at the top right.
5. Copy the generated **Registration Token**.
6. Open your `inventory/group_vars/all.yml` (or `vault.yml`) and paste the token:
   ```yaml
   gitea_runner_registration_token: "YOUR_COPIED_TOKEN_HERE"
   ```
7. Re-apply the Gitea Ansible configuration:
   ```bash
   ansible-playbook site.yml --tags gitea --ask-vault-pass
   ```
   *This automatically recreates the secret and restarts the runner pods, registering them with Gitea.*

If you want to disable the runner, set `gitea_runner_enabled: false` and re-run the `gitea` tag.

The runner is configured with a Docker-in-Docker (`dind`) sidecar container and shares the daemon socket via an `emptyDir` volume. This design ensures compatibility with `containerd` or other non-Docker Kubernetes environments, eliminating the need for a host-level Docker daemon.

---

## CI/CD Pipeline — Example `.woodpecker.yml`

Place this in any Gitea repo to activate CI:

```yaml
# .woodpecker.yml
steps:
  - name: unit-test
    image: golang:1.22         # or node:20, python:3.12, etc.
    commands:
      - go test ./...

  - name: sonar-scan
    image: sonarsource/sonar-scanner-cli:latest
    environment:
      SONAR_HOST_URL: https://sonar.sriitservices.local
      SONAR_TOKEN:
        from_secret: sonar_token
    commands:
      - sonar-scanner -Dsonar.projectKey=${CI_REPO_NAME}
    when:
      branch: [main, develop]

  - name: build-and-push
    image: woodpeckerci/plugin-docker-buildx:latest
    settings:
      registry: registry.sriitservices.local
      repo: registry.sriitservices.local/library/${CI_REPO_NAME}
      tags: [latest, "${CI_COMMIT_SHA:0:8}"]
      username:
        from_secret: harbor_username
      password:
        from_secret: harbor_password
    when:
      branch: main

  - name: update-manifests
    image: alpine/git:latest
    environment:
      GITEA_TOKEN:
        from_secret: gitea_token
    commands:
      - git clone https://gitadmin:$${GITEA_TOKEN}@git.sriitservices.local/team/k8s-manifests.git
      - cd k8s-manifests
      - sed -i "s|image:.*${CI_REPO_NAME}.*|image: registry.sriitservices.local/library/${CI_REPO_NAME}:${CI_COMMIT_SHA:0:8}|" apps/${CI_REPO_NAME}/deployment.yaml
      - git config user.email "ci@sriitservices.com"
      - git config user.name "Woodpecker CI"
      - git commit -am "ci: update ${CI_REPO_NAME} to ${CI_COMMIT_SHA:0:8}" || true
      - git push
    when:
      branch: main

  - name: sync-argocd
    image: argoproj/argocd:v2.11.2
    environment:
      ARGOCD_SERVER:
        from_secret: argocd_server
      ARGOCD_AUTH_TOKEN:
        from_secret: argocd_auth_token
    commands:
      - argocd app sync ${CI_REPO_NAME} --server $${ARGOCD_SERVER} --auth-token $${ARGOCD_AUTH_TOKEN} --insecure
    when:
      branch: main

```

**ArgoCD** watches the `k8s-manifests` repo and automatically deploys the updated image to the cluster.

---

## Persistent Storage — Usage

### Request a Persistent Volume (PVC)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-app-data
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: longhorn          # default, 2 replicas
  # storageClassName: longhorn-fast   # SSD-optimised (databases)
  # storageClassName: longhorn-backup # single replica (logs)
  resources:
    requests:
      storage: 10Gi
```

### Longhorn Scheduling Notes

Longhorn checks storage on a per-disk basis, not by total free space across the whole cluster. A PVC can still stay Pending even when a node looks "70% free" if one of these limits is hit:

- The selected disk does not have enough free space for another replica.
- The storage class requires more replicas than the cluster can place.
- The storage class is restricted to tagged disks, such as `longhorn-fast` using `diskSelector: ssd`.

Default tuning in this repo:

- `longhorn` uses 2 replicas.
- `longhorn-fast` uses 2 replicas and requires SSD-tagged disks.
- `longhorn-backup` uses 1 replica for less critical workloads.
- `storageMinimalAvailablePercentage` is set to `5` to keep Longhorn from blocking too early on small disks.
- `storageOverProvisioningPercentage` is set to `150` to allow some sparse-file headroom.

If a workload does not need high availability, point it at `longhorn-backup` to reduce replica pressure and disk usage.

### Push/Pull Images from Harbor

```bash
# Login
docker login registry.sriitservices.local -u admin

# Tag & push (Trivy auto-scans on push)
docker tag myapp:latest registry.sriitservices.local/library/myapp:latest
docker push registry.sriitservices.local/library/myapp:latest

# Use in a Kubernetes pod
# image: registry.sriitservices.local/library/myapp:latest
```

### Harbor CA Trust

The playbook now copies Harbor's TLS certificate into:

- `/usr/local/share/ca-certificates/registry.sriitservices.local.crt`
- `/etc/containerd/certs.d/registry.sriitservices.local/ca.crt`
- `/etc/docker/certs.d/registry.sriitservices.local/ca.crt`

It also refreshes the system CA bundle. containerd uses the `certs.d` trust directory, so the node-side CA file is enough for image pulls on the standard setup in this repo.

If you need to do the same on a separate Docker build runner, create the Docker trust directory there and restart Docker after placing the CA certificate:

```bash
sudo mkdir -p /etc/docker/certs.d/registry.sriitservices.local
sudo cp harbor-ca.crt /etc/docker/certs.d/registry.sriitservices.local/ca.crt
sudo systemctl restart docker
```

---

## Velero Backup — OneDrive Setup (One-Time)

OneDrive has no native S3 protocol. The architecture is:
```
Velero ──► MinIO (fast, in-cluster) ──► rclone CronJob (nightly) ──► OneDrive
```

### Step 1 — Get OAuth Token (run on your laptop)

```bash
# Install rclone
curl https://rclone.org/install.sh | bash   # Linux/macOS
# Windows: winget install Rclone.Rclone

# Configure OneDrive
rclone config
# → n → name: onedrive → type: 31 (OneDrive) → follow browser flow

# View the generated token
cat ~/.config/rclone/rclone.conf
```

### Step 2 — Add Token to vault.yml

```yaml
# inventory/group_vars/vault.yml
velero_onedrive_token: '{"access_token":"...","token_type":"Bearer","expiry":"..."}'
# For personal OneDrive, leave client_id and client_secret empty
```

### Step 3 — Apply

```bash
ansible-playbook site.yml --tags velero --ask-vault-pass
```

### Backup Commands

```bash
# On-demand backup
velero backup create manual-$(date +%Y%m%d) --include-namespaces databases,harbor

# List backups (also in MinIO)
velero backup get

# Restore
velero restore create --from-backup manual-20260624 --include-namespaces databases
```

---

## File Structure

```
server-setup/
├── ansible.cfg                         # Ansible config (pipelining, SSH multiplex)
├── site.yml                            # ← Main entry point (28 plays)
├── requirements.yml                    # Galaxy collections
├── .gitignore
├── inventory/
│   ├── hosts.yml                       # ← NODE IPs — edit this
│   └── group_vars/
│       ├── all.yml                     # ← All versions / settings
│       └── vault.yml.template          # ← Secrets template (copy → encrypt)
└── roles/
    ├── preflight/          # 01 Pre-flight checks
    ├── common/             # 02 OS baseline
    ├── containerd/         # 03 Container runtime
    ├── kubernetes_binaries/# 04 kubeadm + Helm + repos
    ├── control_plane/      # 05 kubeadm init
    ├── cni/                # 06 Calico / Flannel
    ├── worker_join/        # 07 Join workers
    ├── node_config/        # 08 Labels & taints
    ├── metallb/            # 09 Bare-metal LB
    ├── ingress_nginx/      # 10 NGINX Ingress
    ├── cert_manager/       # 11 TLS automation
    ├── storage_longhorn/   # 12 Distributed storage
    ├── minio/              # 13 S3-compatible object store
    ├── kong/               # 14 Kong API Gateway ← NEW
    ├── harbor_registry/    # 15 Container registry + scanner
    ├── trivy_scanner/      # 16 Vulnerability scanning
    ├── gitea/              # 17 Git service (email auth)
    ├── woodpecker_ci/      # 18 CI pipelines
    ├── argocd/             # 19 GitOps CD
    ├── sonarqube/          # 20 Code quality
    ├── vault_hashicorp/    # 21 Secrets management
    ├── databases/          # 22 PostgreSQL + MySQL + Redis + RabbitMQ
    ├── logging/            # 23 EFK stack
    ├── monitoring/         # 24 Prometheus + Grafana
    ├── wiki_js/            # 25 Team documentation
    ├── mattermost/         # 26 Team chat
    ├── velero/             # 27 Backup + OneDrive sync
    └── validate/           # 28 Post-install smoke tests
```

---

## Post-Deployment Checklist

- [ ] Change **all** `CHANGE_ME` passwords in `vault.yml`
- [ ] Encrypt vault: `ansible-vault encrypt inventory/group_vars/vault.yml`
- [ ] Add DNS records (or `/etc/hosts`) pointing to NGINX Ingress IP
- [ ] *(Optional)* Configure SMTP in `all.yml` for Gitea email confirmation
- [ ] Create Gitea OAuth2 app → set `woodpecker_gitea_client_id/secret` → re-run `--tags woodpecker`
- [ ] Login to ArgoCD → create Applications pointing to your Gitea manifest repos
- [ ] Login to SonarQube → change default `admin/admin` password
- [ ] Unseal **OpenBao** → save unseal keys securely → enable Kubernetes auth
- [ ] Configure Alertmanager receivers (Slack webhook, email, PagerDuty)
- [ ] Set up rclone OneDrive token → re-run `--tags velero`
- [ ] Login to Mattermost → create workspace → add Gitea/ArgoCD/Grafana webhooks
- [ ] Complete Wiki.js setup wizard → optionally enable Gitea Git storage backend
- [ ] Review Trivy scan reports in Harbor UI (Security → Vulnerabilities)
- [ ] Set `gitea_allow_registration: false` after initial team setup

---

## Exposing Services to the Internet (Let's Encrypt TLS)

By default, the platform deploys all services with a `selfsigned-issuer` for safe internal-only use. When you are ready to expose services like Gitea and ArgoCD to the internet, follow these steps to provision and enforce public Let's Encrypt TLS certificates:

### 1. Prerequisites
* **Public DNS Records**: Point your public domain records (e.g., `git.example.com`, `argocd.example.com`) to the external/public IP address of your Ingress Controller (or your network's router/load balancer if port forwarding).
* **Port 80/443 Access**: Cert-manager uses the ACME HTTP-01 challenge. Ensure ports `80` and `443` are open and routed from the internet to your NGINX Ingress Controller.

### 2. Configure cert-manager Email
In [inventory/group_vars/all.yml](file:///D:/Source/sriitservices/server-setup/inventory/group_vars/all.yml#L38), update `cert_manager_email` to a valid email address. This is required by Let's Encrypt for renewal notices:
```yaml
cert_manager_email: "your-email@example.com"
```

### 3. Update Service Configurations to Use Let's Encrypt
To change the certificate issuer from self-signed to Let's Encrypt production, update the hostname and cluster-issuer for the respective services:

#### For ArgoCD:
1. Update `argocd_hostname` in [inventory/group_vars/all.yml](file:///D:/Source/sriitservices/server-setup/inventory/group_vars/all.yml#L225) to your public domain (e.g., `"argocd.example.com"`).
2. Edit [roles/argocd/tasks/main.yml](file:///D:/Source/sriitservices/server-setup/roles/argocd/tasks/main.yml#L66) to change the cluster-issuer:
   ```yaml
   cert-manager.io/cluster-issuer: letsencrypt-prod
   ```

#### For Gitea:
1. Update `gitea_hostname` in [inventory/group_vars/all.yml](file:///D:/Source/sriitservices/server-setup/inventory/group_vars/all.yml#L185) to your public domain (e.g., `"git.example.com"`).
2. Edit [roles/gitea/templates/gitea-ingress.yaml.j2](file:///D:/Source/sriitservices/server-setup/roles/gitea/templates/gitea-ingress.yaml.j2#L10) to change the cluster-issuer:
   ```yaml
   cert-manager.io/cluster-issuer: letsencrypt-prod
   ```

*(You can also use `letsencrypt-staging` first to test the flow without hitting Let's Encrypt production rate limits).*

### 4. Deploy the Changes
Run the Ansible playbook with the tags for the updated components:
```bash
ansible-playbook site.yml --tags "cert_manager,argocd,gitea" --ask-vault-pass
```

### 5. Verify the Certificates
Once deployed, check the status of the certificates inside the cluster and externally:
```bash
# Verify the certificates are READY
kubectl get certificate argocd-tls -n argocd
kubectl get certificate gitea-tls -n devops

# Inspect HTTP SSL handshake externally
curl -Iv https://argocd.example.com
curl -Iv https://git.example.com
```

---

## Troubleshooting

```bash
# Check all nodes are Ready
kubectl get nodes -o wide

# Check all pods (any namespace)
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed

# Describe a failing pod
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous

# Re-run a specific failing role
ansible-playbook site.yml --tags kong -v --ask-vault-pass

# Test Kong proxy
curl -v https://api.sriitservices.local/

# Test Kong Admin API
curl https://kong-admin.sriitservices.local/services

# Velero backup status
velero backup get
velero backup describe <backup-name> --details

# Check rclone OneDrive sync logs
kubectl logs -n velero -l app=velero-onedrive-sync --tail=100

# OpenBao — unseal status
kubectl exec -n vault openbao-0 -- bao status

# OpenBao — unseal (run 3 times with different keys)
kubectl exec -n vault openbao-0 -- bao operator unseal <KEY>

# SSH into a node
ssh -i ~/.ssh/k8s_cluster_key ubuntu@192.168.1.11
```

## SSH Login Options

To avoid repeated prompts during Ansible runs, use one of these approaches:

1. `ssh-copy-id` plus passwordless sudo for the SSH user.
2. Store `ansible_password` and `ansible_become_password` in the encrypted
   `inventory/group_vars/vault.yml` file.
3. If Ansible reports a world-writable directory warning, run with
   `ansible -i inventory/hosts.yml ...` so the repo inventory is used
   explicitly.

---

## Security Notes

> **Before going to production:**
> 1. All secrets must be in an encrypted `vault.yml` — never commit plain text passwords
> 2. Kong Manager and Admin API are restricted to `192.168.0.0/16` — tighten to your office CIDR
> 3. Vault requires manual unseal after every pod restart — consider cloud KMS auto-unseal
> 4. Rotate Let's Encrypt from `selfsigned-issuer` to `letsencrypt-prod` once DNS is live
> 5. Set `gitea_allow_registration: false` once your team accounts are created
> 6. Review and act on Trivy vulnerability reports regularly
> 7. Enable Kubernetes Network Policies to restrict pod-to-pod traffic
