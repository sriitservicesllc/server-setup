# 🌐 Multi-Environment Setup & Architecture Design

This document details the architectural boundaries, service topology, and bootstrapping procedures for the **Dev/Management**, **UAT**, and **Production** Kubernetes clusters.

---

## 1. Architectural Strategy & Isolation

To minimize the blast radius, ensure strict security boundaries, and optimize resource usage, the platform is divided into three distinct clusters:

```
                  ┌──────────────────────────────────────────────┐
                  │                 LAN / WAN                    │
                  └──────┬──────────────┬──────────────┬─────────┘
                         │              │              │
        ┌────────────────▼┐    ┌────────▼────────┐    ┌▼────────────────┐
        │   DEV / MGMT    │    │       UAT       │    │   PRODUCTION    │
        │   1 Master      │    │    1 Master     │    │   3 Masters (HA)│
        │   2 Workers     │    │    2 Workers    │    │   3+ Workers    │
        ├─────────────────┤    ├─────────────────┤    ├─────────────────┤
        │  Gitea & CI/CD  │    │  UAT Apps       │    │  Prod Apps      │
        │  Harbor Registry│    │  UAT Databases  │    │  Prod Databases │
        │  SonarQube      │    │  Ingress/TLS    │    │  HA Longhorn    │
        │  OpenBao (Main) │    │  (No Toolchain) │    │  Logging (EFK)  │
        │  Dev App Sandbk │    │                 │    │  Prom/Grafana   │
        └─────────────────┘    └─────────────────┘    └─────────────────┘
```

1. **Dev/Management Cluster**: Holds the shared developmental toolchain, security registry, source control, and a sandbox environment for initial developer testing.
2. **UAT (User Acceptance Testing) Cluster**: Isolated cluster to test applications in a production-like staging environment. No development tools or registries run here. It pulls images from the Harbor registry located in the Dev cluster.
3. **Production Cluster**: Highly available, hardened, and instrumented. Deploys a Multi-Master (HA) control plane and distributed state engines. Access is strictly controlled, and deployments are executed solely via GitOps (ArgoCD) pointing from the Dev Git repo.

---

## 2. Environment Comparison & Service Mapping

| Component / Service | Dev / Mgmt | UAT | Production | Notes |
|:---|:---:|:---:|:---:|:---|
| **K8s Master Nodes** | 1 Node | 1 Node | **3 Nodes (HA)** | Production requires quorum (`etcd` parity). |
| **K8s Worker Nodes** | 2 Nodes | 2 Nodes | 3+ Nodes | Scale worker nodes as workload demands. |
| **MetalLB** | Yes | Yes | Yes | Allocates local virtual IPs. |
| **NGINX Ingress** | Yes | Yes | Yes | Handles SSL/TLS termination. |
| **cert-manager** | Yes | Yes | Yes | Dev/UAT uses Self-Signed; Prod uses Let's Encrypt. |
| **Longhorn Storage** | Yes (2 repl) | Yes (2 repl) | **Yes (3 replicas)** | Prod requires higher availability and rack isolation. |
| **MinIO (Object Storage)**| Yes | Yes | Yes | Hosts backups & state attachments. |
| **Kong API Gateway** | Yes | Yes | Yes | Public ingress gate. |
| **Harbor Registry** | **Yes** | No | No | Dev hosts the shared company registry. |
| **Gitea (Git Server)** | **Yes** | No | No | Dev hosts the canonical code repository. |
| **Woodpecker CI** | **Yes** | No | No | Pipelines run on Dev cluster agents. |
| **ArgoCD (GitOps)** | **Yes** | No | **Yes (Targeted)** | Prod runs its own local sync agent for safety. |
| **SonarQube** | **Yes** | No | No | Code scanning occurs during Dev CI pipelines. |
| **OpenBao (Vault)** | **Yes (Main)** | Yes (Agent) | **Yes (HA Vault)** | Production runs local Vault for pod secret injection. |
| **PostgreSQL / MySQL** | Single | HA (2 nodes) | **Multi-AZ HA** | Production database has secondary read replicas. |
| **Redis / RabbitMQ** | Single | Sentinel | **Clustered HA** | Message queues and caching are fully distributed in Prod. |
| **Logging (EFK Stack)** | No | No | **Yes** | Log aggregation (Fluent Bit/Elastic) runs in Prod. |
| **Monitoring (Prometheus)**| Yes (Light) | Yes (Light) | **Yes (Full)** | Production features advanced Alertmanager triggers. |
| **Velero Backups** | Daily | Daily | **Hourly + DR Sync** | Production synchronizes off-site hourly. |

---

## 3. Production Cluster Spec: Multi-Master & High Availability

To eliminate the single point of failure (SPOF) on the control plane, the Production environment deploys **3 Master Nodes** backed by a load balancer.

### High Availability Control Plane Architecture
```
                     VIP: 192.168.1.199:6443 (Keepalived / HAProxy)
                                     │
             ┌───────────────────────┼───────────────────────┐
             ▼                       ▼                       ▼
    ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
    │    master-01    │     │    master-02    │     │    master-03    │
    │  192.168.1.100  │     │  192.168.1.101  │     │  192.168.1.102  │
    │ (etcd leader)   │     │ (etcd follower) │     │ (etcd follower) │
    └─────────────────┘     └─────────────────┘     └─────────────────┘
```

#### Keepalived & HAProxy Configuration (Run on all Masters)
A Virtual IP (VIP) is shared between the masters using Keepalived. HAProxy runs on port `6443` (redirecting traffic to local/remote api-servers on internal ports).

* **HAProxy Configuration (`/etc/haproxy/haproxy.cfg`)**:
```haproxy
frontend k8s-api
    bind 0.0.0.0:6443
    mode tcp
    option tcplog
    default_backend k8s-masters

backend k8s-masters
    mode tcp
    option tcplog
    balance roundrobin
    default-server inter 10s fall 2 rise 290
    server master-01 192.168.1.100:6443 check
    server master-02 192.168.1.101:6443 check
    server master-03 192.168.1.102:6443 check
```

* **Keepalived Configuration (`/etc/keepalived/keepalived.conf` on master-01)**:
```text
vrrp_script check_apiserver {
    script "/usr/bin/killall -0 haproxy"
    interval 2
    weight 2
}

vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 101
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass K8sHaSecr3t
    }
    virtual_ipaddress {
        192.168.1.199
    }
    track_script {
        check_apiserver
    }
}
```
*(On master-02 and master-03, set `state BACKUP` and `priority 100` / `99` respectively).*

---

## 4. Step-by-Step Environment Bootstrapping

We structure our Ansible inventory configurations separately to bootstrap each cluster with its target environment role.

### Step 1: Create Host Inventories
Ensure you have the following host files in your `inventory/` directory:
* `inventory/hosts-dev.yml`
* `inventory/hosts-uat.yml`
* `inventory/hosts-prod.yml`

#### Example Production Inventory (`inventory/hosts-prod.yml`)
```yaml
k8s_masters:
  hosts:
    master-01:
      ansible_host: 192.168.1.100
    master-02:
      ansible_host: 192.168.1.101
    master-03:
      ansible_host: 192.168.1.102

k8s_workers:
  hosts:
    worker-01:
      ansible_host: 192.168.1.103
    worker-02:
      ansible_host: 192.168.1.104
    worker-03:
      ansible_host: 192.168.1.105

k8s_cluster:
  children:
    k8s_masters:
    k8s_workers:
```

### Step 2: Configure Environment Variables
Inside `inventory/group_vars/`, override variables specific to each environment:

* **Production Variables (`inventory/group_vars/prod_vars.yml`)**:
```yaml
# Use Let's Encrypt for public SSL/TLS certificates
cert_manager_email: "security@sriitservices.com"
cert_issuer_name: "letsencrypt-prod"

# Production Longhorn storage config
longhorn_replica_count: 3

# Cluster API Endpoint (VIP)
k8s_api_server_ip: "192.168.1.199"

# Disable in-cluster development tools
gitea_enabled: false
woodpecker_enabled: false
sonarqube_enabled: false
harbor_enabled: false
```

### Step 3: Run target deployments

#### Bootstrapping Dev & Tooling Cluster:
```bash
ansible-playbook site.yml -i inventory/hosts-dev.yml --ask-vault-pass
```

#### Bootstrapping UAT Cluster:
```bash
ansible-playbook site.yml -i inventory/hosts-uat.yml --ask-vault-pass --tags "bootstrap,networking,databases"
```

#### Bootstrapping Production Cluster:
Before running, make sure Keepalived and HAProxy are active on the master nodes to bind the API Virtual IP (`192.168.1.199`).
```bash
# Deploy base cluster OS + containerd + kubeadm
ansible-playbook site.yml -i inventory/hosts-prod.yml --tags "bootstrap,common,containerd" --ask-vault-pass

# Initialize HA Master-01
# (Executed manually or targeted in playbooks using control-plane-endpoint)
# kubeadm init --control-plane-endpoint "192.168.1.199:6443" --upload-certs --pod-network-cidr=10.244.0.0/16

# Run full production infrastructure deployment
ansible-playbook site.yml -i inventory/hosts-prod.yml --ask-vault-pass
```

---

## 5. Production Disaster Recovery (DR) & Backup Replication Scheme

Production database backups and cluster configurations require automated Off-Site synchronization to satisfy the **3-2-1 backup strategy** (3 copies of data, on 2 different media, with 1 copy off-site).

```
 ┌────────────────────────────────────────────────────────┐
 │                   PRODUCTION CLUSTER                   │
 │                                                        │
 │  ┌─────────────┐    Velero Snap    ┌────────────────┐  │
 │  │ databases   │──────────────────►│ MinIO (Local)  │  │
 │  │ workloads   │                   │ (Bucket: prod) │  │
 │  └─────────────┘                   └───────┬────────┘  │
 └────────────────────────────────────────────┼───────────┘
                                              │ Nightly Cron
                                              ▼
                                      ┌───────────────┐
                                      │ OneDrive Sync │
                                      │ (Off-Site DR) │
                                      └───────────────┘
```

### 1. Daily Backup Schedule
Velero is configured in the Production cluster to snapshot all stateful namespaces (including databases and application config) every hour:
```bash
velero schedule create prod-hourly-backup --schedule="0 * * * *" --include-namespaces databases,apps --ttl 168h0m0s
```

### 2. Warm Standby Disaster Recovery Procedure
In the event that the primary Production cluster is completely lost (e.g., power grid failure at the primary site):

1. **Activate the Passive DR Cluster** (located in a secondary data center / network subnet).
2. **Retrieve the latest RClone backups** from OneDrive:
   Ensure the standby cluster's local MinIO registry is hydrated with the backup tarballs stored on OneDrive.
3. **Connect Velero on the DR Cluster** to the target MinIO bucket:
   ```yaml
   apiVersion: velero.io/v1
   kind: BackupStorageLocation
   metadata:
     name: default
     namespace: velero
   spec:
     provider: aws
     objectStorage:
       bucket: velero-backups
     config:
       s3Url: http://dr-minio.sriitservices.local:9000
       publicUrl: http://dr-minio.sriitservices.local:9000
   ```
4. **List available backups**:
   ```bash
   velero backup get
   ```
5. **Restore workloads to the DR Cluster**:
   ```bash
   velero restore create --from-backup prod-hourly-backup-<TIMESTAMP> --restore-volumes=true
   ```
6. **Switch DNS records**: Update internal/public DNS to route traffic to the DR cluster Ingress IP (`192.168.1.250`).
