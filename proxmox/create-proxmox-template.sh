#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Configuration Variables (Modify these to match your environment)
# ==============================================================================
VM_ID=9000
VM_NAME="ubuntu-2404-template"
STORAGE_POOL="local-lvm"          # e.g., local-lvm, local-zfs, ceph
BRIDGE="vmbr0"
CORES=2
MEMORY=2048                       # in MB
IMAGE_URL="https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
IMAGE_FILE="/tmp/ubuntu-24.04-server-cloudimg-amd64.img"

# ==============================================================================
# Safety Checks
# ==============================================================================
if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] This script must be run as root on the Proxmox host." >&2
   exit 1
fi

if qm status "$VM_ID" &>/dev/null; then
    echo "[ERROR] VM ID $VM_ID already exists. Destroy it or change VM_ID." >&2
    exit 1
fi

# ==============================================================================
# Step 1: Install prerequisites and download image
# ==============================================================================
echo "[1/5] Ensuring libguestfs-tools is installed..."
if ! command -v virt-customize &>/dev/null; then
    apt update && apt install -y libguestfs-tools
fi

echo "[2/5] Downloading Ubuntu Cloud Image..."
rm -f "$IMAGE_FILE"
wget -q --show-progress -O "$IMAGE_FILE" "$IMAGE_URL"

echo "[3/5] Injecting qemu-guest-agent into image..."
virt-customize -a "$IMAGE_FILE" --install qemu-guest-agent

# ==============================================================================
# Step 2: Create VM and attach hardware
# ==============================================================================
echo "[4/5] Creating base VM definition ($VM_ID)..."
qm create "$VM_ID" \
    --name "$VM_NAME" \
    --memory "$MEMORY" \
    --cores "$CORES" \
    --cpu host \
    --net0 virtio,bridge="$BRIDGE" \
    --scsihw virtio-scsi-pci \
    --agent enabled=1

echo "Importing disk to storage '$STORAGE_POOL'..."
# Disk import naming format differs by storage type; capture the disk path directly
IMPORTED_DISK=$(qm importdisk "$VM_ID" "$IMAGE_FILE" "$STORAGE_POOL" --format raw 2>&1 | awk '/Successfully imported disk as/ {print $NF}')

# Fallback check if the string format is plain volume ID
if [[ -z "$IMPORTED_DISK" ]]; then
    IMPORTED_DISK=$(qm config "$VM_ID" | grep -o "$STORAGE_POOL:vm-$VM_ID-disk-[0-9]" || true)
fi

echo "Configuring disk drives and Cloud-Init..."
qm set "$VM_ID" --scsihw virtio-scsi-pci --scsi0 "$IMPORTED_DISK"
qm set "$VM_ID" --boot order=scsi0
qm set "$VM_ID" --ide2 "$STORAGE_POOL:cloudinit"
qm set "$VM_ID" --serial0 socket --vga serial0

# ==============================================================================
# Step 3: Convert to Template & Cleanup
# ==============================================================================
echo "[5/5] Converting VM $VM_ID to a template..."
qm template "$VM_ID"

rm -f "$IMAGE_FILE"
echo "=== Success! Template '$VM_NAME' (ID: $VM_ID) created successfully. ==="