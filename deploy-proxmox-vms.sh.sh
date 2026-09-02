#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Base Configuration
# ==============================================================================
TEMPLATE_ID=9000
CI_USER="adminuser"
CI_PASSWORD="ChangeMeImmediately123!"     # Or leave empty if using SSH keys exclusively
SSH_KEY_PATH="$HOME/.ssh/id_rsa.pub"      # Public key injected for passwordless login
DISK_SIZE_ADD="+20G"                      # Storage added on top of the base image
START_ON_CREATION=true

# Gateway and DNS (Used if assigning static IPs)
GATEWAY="192.168.1.1"
NAMESERVER="1.1.1.1"

# ==============================================================================
# Define VMs to Deploy
# Format: "VM_ID:VM_NAME:IP_ADDRESS_WITH_CIDR:CORES:MEMORY_MB"
# Use "dhcp" instead of an IP/CIDR to let your router assign the address.
# ==============================================================================
VMS=(
    "201:web-node-01:192.168.1.51/24:2:4096"
    "202:db-node-01:192.168.1.52/24:4:8192"
    "203:app-node-01:dhcp:2:2048"
)

# ==============================================================================
# Pre-flight Checks
# ==============================================================================
if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] This script must be run as root on the Proxmox host." >&2
   exit 1
fi

if ! qm status "$TEMPLATE_ID" &>/dev/null; then
    echo "[ERROR] Template ID $TEMPLATE_ID does not exist." >&2
    exit 1
fi

SSH_KEY_PARAM=()
if [[ -f "$SSH_KEY_PATH" ]]; then
    SSH_KEY_PARAM=(--sshkeys "$SSH_KEY_PATH")
else
    echo "[WARN] Public key '$SSH_KEY_PATH' not found. Deploying without injected SSH key file."
fi

# ==============================================================================
# Deployment Loop
# ==============================================================================
for vm in "${VMS[@]}"; do
    IFS=":" read -r VM_ID VM_NAME VM_IP CORES MEMORY <<< "$vm"

    echo "--------------------------------------------------------"
    echo "Provisioning VM: $VM_NAME (ID: $VM_ID)..."

    # Check if VM already exists
    if qm status "$VM_ID" &>/dev/null; then
        echo "[SKIP] VM ID $VM_ID already exists. Skipping."
        continue
    fi

    # 1. Full clone from base template
    echo "-> Cloning from template $TEMPLATE_ID..."
    qm clone "$TEMPLATE_ID" "$VM_ID" --name "$VM_NAME" --full 1

    # 2. Update resource allocations
    echo "-> Setting CPU ($CORES cores) and RAM (${MEMORY}MB)..."
    qm set "$VM_ID" --cores "$CORES" --memory "$MEMORY"

    # 3. Resize base disk
    echo "-> Expanding disk by $DISK_SIZE_ADD..."
    qm resize "$VM_ID" scsi0 "$DISK_SIZE_ADD"

    # 4. Set Cloud-Init Network Configuration
    if [[ "$VM_IP" == "dhcp" ]]; then
        echo "-> Configuring Cloud-Init for DHCP..."
        qm set "$VM_ID" --ipconfig0 ip=dhcp
    else
        echo "-> Configuring Cloud-Init static IP: $VM_IP (GW: $GATEWAY)..."
        qm set "$VM_ID" --ipconfig0 "ip=$VM_IP,gw=$GATEWAY" --nameserver "$NAMESERVER"
    fi

    # 5. Set Cloud-Init User & Credentials
    echo "-> Applying credentials..."
    qm set "$VM_ID" \
        --ciuser "$CI_USER" \
        --cipassword "$CI_PASSWORD" \
        "${SSH_KEY_PARAM[@]}"

    # 6. Start the VM
    if [ "$START_ON_CREATION" = true ]; then
        echo "-> Starting VM $VM_ID..."
        qm start "$VM_ID"
    fi

    echo "[DONE] Successfully deployed $VM_NAME (ID: $VM_ID)."
done

echo "--------------------------------------------------------"
echo "All deployments completed."