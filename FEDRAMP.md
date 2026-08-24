# Hardened FedRAMP Kubernetes Cluster Infrastructure

This repository provisions a secure, production-ready Kubernetes cluster hardened to align with **FedRAMP (NIST SP 800-53 Rev. 5)** security controls. It builds upon base server automation setups by enforcing FIPS 140-2/3 cryptography, strict RBAC/OIDC access controls, mandatory admission policies, network-level encryption, and centralized audit logging.

---

## Architecture Overview

```
                          +-------------------------------------------------+
                          |               FedRAMP Boundary                  |
                          |  (AWS GovCloud / Azure Gov / GCP Assured)       |
                          +-------------------------------------------------+
                                                  |
                                                  v
     +---------------------------------------------------------------------------------+
     |                               Control Plane Nodes                               |
     |  - Host OS: RHEL / Ubuntu Pro (FIPS Mode Enabled + CIS Hardened)                 |
     |  - kube-apiserver: OIDC Auth (MFA), TLS 1.3 Ciphers, Verbose Audit Logging      |
     |  - etcd: Encrypted at Rest via AWS KMS / HashiCorp Vault (FIPS Provider)         |
     +---------------------------------------------------------------------------------+
                                                  |
                       +--------------------------+--------------------------+
                       | (mTLS / Wireguard Encrypted CNI Mesh)               |
                       v                                                     v
+---------------------------------------------+       +---------------------------------------------+
|                Worker Node 1                |       |                Worker Node 2                |
|  - Containerd (FIPS Crypto Modules)         |       |  - Containerd (FIPS Crypto Modules)         |
|  - Runtime Threat Detection (Falco / eBPF)  |       |  - Runtime Threat Detection (Falco / eBPF)  |
|  - Kyverno / Gatekeeper Admission Controls  |       |  - Kyverno / Gatekeeper Admission Controls  |
|  - Default Deny NetworkPolicy               |       |  - Default Deny NetworkPolicy               |
+---------------------------------------------+       +---------------------------------------------+
                       |                                                     |
                       +--------------------------+--------------------------+
                                                  | (Immutable Syslog / Audit Stream)
                                                  v
                               +-------------------------------------+
                               |          Centralized SIEM           |
                               | (Splunk / Elastic - Write Once/WORM)|
                               +-------------------------------------+
```

---

## FedRAMP Control Mapping

| NIST SP 800-53 Control | Requirement | Cluster Implementation Details |
| :--- | :--- | :--- |
| **AC-2, AC-3, AC-6** | Least Privilege & Identity Management | OIDC integration for API server authentication with MFA. Anonymous access disabled. K8s RBAC enforced. |
| **SC-8, SC-8(1)** | Transmission Confidentiality | Pod-to-pod and node-to-node traffic encrypted using Cilium WireGuard/IPsec mesh. TLS 1.2+ for ingress. |
| **SC-12, SC-13** | Cryptographic Key & Module Protection | Host OS and container engines operate strictly in **FIPS 140-2/3 mode**. |
| **SC-28** | Protection of Information at Rest | `etcd` database encrypted using AWS KMS/Vault provider configuration. Persistent volumes encrypted via cloud KMS keys. |
| **AU-2, AU-6, AU-12** | Audit Record Generation & Analysis | Control plane audit policy enabled. Fluentbit streams logs to an off-cluster, tamper-proof SIEM target. |
| **CM-6, CM-7** | Configuration Settings & Least Functionality | CIS Kubernetes Benchmark hardened baseline. Kyverno admission controller blocks non-root execution and privileged containers. |
| **SI-4** | System Monitoring & Runtime Security | eBPF-based threat monitoring (Falco) installed on worker nodes to flag anomalous execution. |

---

## Prerequisites

Before deploying the cluster automation, ensure you have the following environment and credentials prepared:

- **Target Environment:** FedRAMP-authorized cloud boundary (e.g., AWS GovCloud, Azure Government, GCP Assured Workloads).
- **Base Image:** FIPS-capable Linux AMI/Image (e.g., Red Hat Enterprise Linux 8/9 with FIPS active, Ubuntu Pro FIPS).
- **Identity Provider (IdP):** OIDC-compliant IdP (Okta, Keycloak, Entra ID) configured with MFA.
- **KMS Endpoint:** KMS Key ARN or Vault URL for `etcd` envelopment encryption.
- **Tools:** `ansible` >= 2.15, `terraform` >= 1.5, `kubectl`, `helm`.

---

## Installation & Deployment

### Step 1: Pre-Flight Node Hardening (Host OS)

Run the host configuration scripts to enforce kernel-level FIPS mode and apply CIS OS benchmarks:

```bash
# Verify FIPS is enabled on all target hosts
cat /proc/sys/crypto/fips_enabled
# Output MUST be 1

# Execute host baseline hardening via Ansible
ansible-playbook -i inventory/hosts playbooks/01-os-hardening.yml
```

### Step 2: Provision Infrastructure & Control Plane

Bootstrap the cluster control plane with KMS encryption and OIDC flags enabled:

```bash
# Provision etcd encryption configuration
cp templates/encryption-config.yaml.example /etc/kubernetes/enc/encryption-config.yaml

# Initialize control plane via hardened setup script
./scripts/02-init-control-plane.sh \
  --oidc-issuer-url="https://idp.fedramp-gov.com/oauth2/v1" \
  --oidc-client-id="k8s-apiserver" \
  --kms-key-arn="arn:aws-us-gov:kms:us-gov-west-1:123456789012:key/abc-123"
```

### Step 3: Deploy Network Encryption & Admission Controls

Apply the encrypted CNI mesh and workload admission rules once nodes have joined:

```bash
# Install Cilium CNI with transparent WireGuard encryption
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium \
  --namespace kube-system \
  --set encryption.enabled=true \
  --set encryption.type=wireguard

# Deploy Kyverno policy engine & FedRAMP baseline rules
kubectl apply -f policies/kyverno/
```

### Step 4: Enable Continuous Audit Forwarding

Stream cluster audit events off-node immediately:

```bash
# Deploy Fluentbit audit log collector daemonset
kubectl apply -f manifests/logging/audit-daemonset.yaml
```

---

## Verification & Compliance Auditing

Validate the deployment against 3PAO auditing standards using built-in automation:

1. **CIS Benchmark Audit:**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml
   kubectl logs job/kube-bench
   ```
2. **Admission Policy Verification:**
   ```bash
   # Test blocking of unauthorized root execution (Must Fail)
   kubectl apply -f tests/disallowed-root-pod.yaml
   ```
3. **FIPS Validation:**
   ```bash
   # Check container engine crypto status
   kubectl get nodes -o jsonpath='{.items[*].status.nodeInfo.kernelVersion}'
   ```

---

## Repository Structure

```
.
├── docs/                   # FedRAMP System Security Plan (SSP) control mapping attachments
├── inventory/              # Cluster host inventories
├── manifests/
│   ├── apiserver/          # EncryptionConfiguration and AuditPolicy definitions
│   ├── logging/            # SIEM log aggregation DaemonSets
│   └── network/            # Default-deny NetworkPolicies
├── policies/
│   └── kyverno/            # Admission control policies (non-root, read-only root, signed images)
├── playbooks/              # Ansible playbooks for OS/FIPS STIG hardening
└── scripts/                # Bootstrap and validation scripts
```

---

## Operational Disclaimer


> **Important:** Running this setup automates technical controls required for FedRAMP alignment. However, FedRAMP authorization requires complete operational documentation, continuous monitoring procedures, independent 3PAO assessment, and formal agency sponsorship.
