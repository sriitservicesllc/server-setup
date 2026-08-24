#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: 02-init-control-plane.sh
# Objective: Bootstrap a FedRAMP-Compliant Kubernetes Control Plane
# Alignments: NIST SP 800-53 (AC-2, AU-2, AU-12, SC-8, SC-13, SC-28)
# ==============================================================================

# Default Parameters
OIDC_ISSUER_URL=""
OIDC_CLIENT_ID="k8s-apiserver"
KMS_KEY_ARN=""
POD_CIDR="10.244.0.0/16"
SERVICE_CIDR="10.96.0.0/12"
K8S_VERSION="v1.30.0"

# Parse CLI Flags
while [[ $# -gt 0 ]]; do
  case $1 in
    --oidc-issuer-url=*)
      OIDC_ISSUER_URL="${1#*=}"
      shift
      ;;
    --oidc-client-id=*)
      OIDC_CLIENT_ID="${1#*=}"
      shift
      ;;
    --kms-key-arn=*)
      KMS_KEY_ARN="${1#*=}"
      shift
      ;;
    *)
      echo "Unknown flag: $1"
      exit 1
      ;;
  esac
done

if [[ -z "${OIDC_ISSUER_URL}" ]]; then
  echo "Error: --oidc-issuer-url is required for FedRAMP AC-2 compliance."
  exit 1
fi

echo "[1/5] Verifying FIPS Environment..."
if [[ $(cat /proc/sys/crypto/fips_enabled 2>/dev/null) != "1" ]]; then
  echo "CRITICAL: Host OS is not running in FIPS mode (/proc/sys/crypto/fips_enabled != 1). Aborting."
  exit 1
fi

echo "[2/5] Creating Audit Policy and Encryption Directory Structure..."
mkdir -p /etc/kubernetes/audit /etc/kubernetes/enc /var/log/kubernetes

# Create Audit Policy (NIST SP 800-53 AU-2 / AU-12)
cat <<'EOF' > /etc/kubernetes/audit/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Do not log noisy read requests
  - level: None
    resources:
      - group: ""
        resources: ["endpoints", "services", "configmaps"]
  # Log Secret access at RequestResponse level (Metadata only for security)
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets", "serviceaccounts"]
  # Log control plane changes at RequestResponse
  - level: RequestResponse
    verbs: ["update", "patch", "delete", "create"]
  # Default catch-all
  - level: Metadata
    omitStages:
      - "RequestReceived"
EOF

# Create KMS Encryption Config Template (NIST SP 800-53 SC-28)
cat <<EOF > /etc/kubernetes/enc/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
      - configmaps
    providers:
      - kms:
          name: aws-kms-provider
          endpoint: unix:///var/run/kmsplugin/socket.sock
          cachesize: 100
          timeout: 3s
      - aescbc:
          keys:
            - name: fallback-key
              secret: $(head -c 32 /dev/urandom | base64)
EOF

chmod 600 /etc/kubernetes/enc/encryption-config.yaml
chmod 600 /etc/kubernetes/audit/audit-policy.yaml

echo "[3/5] Generating kubeadm Configuration File..."
NODE_IP=$(hostname -I | awk '{print $1}')

cat <<EOF > /tmp/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
  kubeletExtraArgs:
    anonymous-auth: "false"
    tls-cipher-suites: "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
    read-only-port: "0"
    protect-kernel-defaults: "true"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: "${K8S_VERSION}"
networking:
  podSubnet: "${POD_CIDR}"
  serviceSubnet: "${SERVICE_CIDR}"
apiServer:
  extraArgs:
    anonymous-auth: "false"
    tls-cipher-suites: "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
    encryption-provider-config: "/etc/kubernetes/enc/encryption-config.yaml"
    audit-policy-file: "/etc/kubernetes/audit/audit-policy.yaml"
    audit-log-path: "/var/log/kubernetes/audit.log"
    audit-log-maxage: "30"
    audit-log-maxbackup: "10"
    audit-log-maxsize: "100"
    oidc-issuer-url: "${OIDC_ISSUER_URL}"
    oidc-client-id: "${OIDC_CLIENT_ID}"
    oidc-username-claim: "email"
    oidc-groups-claim: "groups"
    profiling: "false"
  extraVolumes:
    - name: audit-policy
      hostPath: /etc/kubernetes/audit
      mountPath: /etc/kubernetes/audit
      readOnly: true
    - name: audit-logs
      hostPath: /var/log/kubernetes
      mountPath: /var/log/kubernetes
      readOnly: false
    - name: enc-config
      hostPath: /etc/kubernetes/enc
      mountPath: /etc/kubernetes/enc
      readOnly: true
etcd:
  local:
    extraArgs:
      cipher-suites: "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
EOF

echo "[4/5] Initializing Kubernetes Cluster Control Plane..."
kubeadm init --config=/tmp/kubeadm-config.yaml --upload-certs

echo "[5/5] Configuring Local Kubeconfig..."
mkdir -p "${HOME}/.kube"
cp -i /etc/kubernetes/admin.conf "${HOME}/.kube/config"
chown "$(id -u):$(id -g)" "${HOME}/.kube/config"

rm -f /tmp/kubeadm-config.yaml

echo "=============================================================================="
echo "Control plane successfully bootstrapped with FedRAMP hardening controls."
echo "Remember to back up /etc/kubernetes/enc/encryption-config.yaml securely."
echo "=============================================================================="
