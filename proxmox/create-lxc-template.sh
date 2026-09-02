#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
CT_ID=8000
CT_NAME="debian-base-template"
STORAGE_POOL="local-lvm"          # Storage for rootfs (local-lvm, local-zfs, etc.)
TEMPLATE_STORAGE="local"          # Storage where downloaded appliance tarballs live
BRIDGE="vmbr0"
DISK_SIZE="8"
CORES=2
MEMORY=1024                       # in MB

# ==============================================================================
# Pre-checks
# ==============================================================================
if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] Must run as root on the Proxmox host." >&2
   exit 1
fi

if pct status "$CT_ID" &>/dev/null; then
    echo "[ERROR] CT ID $CT_ID already exists. Destroy it or pick a new ID." >&2
    exit 1
fi

# ==============================================================================
# 1. Dynamically find and download the latest Debian 12 appliance
# ==============================================================================
echo "[1/4] Updating appliance list..."
pveam update

echo "Finding latest Debian 12 appliance..."
OS_APPLIANCE=$(pveam available -section system | awk '{print $2}' | grep -E '^debian-12-standard' | sort -V | tail -n 1)

if [[ -z "$OS_APPLIANCE" ]]; then
    echo "[ERROR] Could not find a Debian 12 standard template in pveam." >&2
    exit 1
fi

echo "Selected template: $OS_APPLIANCE"

if ! pveam list "$TEMPLATE_STORAGE" | grep -q "$OS_APPLIANCE"; then
    echo "Downloading $OS_APPLIANCE to $TEMPLATE_STORAGE..."
    pveam download "$TEMPLATE_STORAGE" "$OS_APPLIANCE"
else
    echo "Template already cached on $TEMPLATE_STORAGE."
fi

# ==============================================================================
# 2. Create the base Container
# ==============================================================================
echo "[2/4] Creating container $CT_ID..."
pct create "$CT_ID" "$TEMPLATE_STORAGE:vztmpl/$OS_APPLIANCE" \
    --hostname "$CT_NAME" \
    --cores "$CORES" \
    --memory "$MEMORY" \
    --swap 512 \
	--rootfs "volume=${STORAGE_POOL}:${DISK_SIZE}" \
    --net0 name=eth0,bridge="$BRIDGE",ip=dhcp \
    --unprivileged 1 \
    --features nesting=1 \
    --onboot 0

# ==============================================================================
# 3. Provision base packages & baseline setup
# ==============================================================================
echo "[3/4] Booting temporarily to configure base packages..."
pct start "$CT_ID"

# Wait for container networking to come up
sleep 5

echo "Installing base tools inside container..."
pct exec "$CT_ID" -- apt update
pct exec "$CT_ID" -- apt install -y curl wget sudo openssh-server ca-certificates

echo "Cleaning up apt caches..."
pct exec "$CT_ID" -- apt clean
pct exec "$CT_ID" -- rm -rf /var/lib/apt/lists/*

echo "Stopping container..."
pct stop "$CT_ID"

# ==============================================================================
# 4. Convert to Template
# ==============================================================================
echo "[4/4] Converting CT $CT_ID to template..."
pct template "$CT_ID"

echo "=== Success! LXC Template '$CT_NAME' (ID: $CT_ID) is ready. ==="