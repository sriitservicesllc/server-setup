#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
TEMPLATE_ID=8000
BRIDGE="vmbr0"
GATEWAY="192.168.1.1"
NAMESERVER="1.1.1.1"
ROOT_PASSWORD="ChangeMeInProd123!"
SSH_KEY_PATH="$HOME/.ssh/id_rsa.pub"
START_ON_CREATION=true

# Format: "CT_ID:HOSTNAME:IP_WITH_CIDR:CORES:MEMORY_MB:DISK_SIZE"
# Use "dhcp" for IP if you want router assignment
CONTAINERS=(
    "301:lxc-web-01:192.168.1.71/24:2:2048:16G"
    "302:lxc-cache-01:192.168.1.72/24:2:1024:8G"
    "303:lxc-dns-01:dhcp:1:512:4G"
)

# ==============================================================================
# Pre-checks
# ==============================================================================
if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] Must run as root on the Proxmox host." >&2
   exit 1
fi

if ! pct status "$TEMPLATE_ID" &>/dev/null; then
    echo "[ERROR] Template ID $TEMPLATE_ID does not exist." >&2
    exit 1
fi

# ==============================================================================
# Deployment Loop
# ==============================================================================
for ct in "${CONTAINERS[@]}"; do
    IFS=":" read -r CT_ID CT_NAME CT_IP CORES MEMORY DISK_SIZE <<< "$ct"

    echo "--------------------------------------------------------"
    echo "Deploying LXC: $CT_NAME (ID: $CT_ID)..."

    if pct status "$CT_ID" &>/dev/null; then
        echo "[SKIP] Container $CT_ID already exists. Skipping."
        continue
    fi

    # 1. Clone from template (full clone)
    echo "-> Cloning template $TEMPLATE_ID..."
    pct clone "$TEMPLATE_ID" "$CT_ID" --hostname "$CT_NAME" --full 1

    # 2. Resize root disk
    echo "-> Setting disk size to $DISK_SIZE..."
    pct resize "$CT_ID" rootfs "$DISK_SIZE"

    # 3. Configure hardware limits
    echo "-> Setting CPU ($CORES cores) and RAM (${MEMORY}MB)..."
    pct set "$CT_ID" --cores "$CORES" --memory "$MEMORY"

    # 4. Set network configuration
    if [[ "$CT_IP" == "dhcp" ]]; then
        echo "-> Configuring DHCP networking..."
        pct set "$CT_ID" --net0 name=eth0,bridge="$BRIDGE",ip=dhcp
    else
        echo "-> Configuring static IP: $CT_IP..."
        pct set "$CT_ID" --net0 "name=eth0,bridge=$BRIDGE,ip=$CT_IP,gw=$GATEWAY" \
                         --nameserver "$NAMESERVER"
    fi

    # 5. Inject SSH Key and root password
    if [[ -f "$SSH_KEY_PATH" ]]; then
        echo "-> Injecting SSH authorized key..."
        pct set "$CT_ID" --ssh-public-keys "$SSH_KEY_PATH"
    fi

    # Set root password inside container
    echo "root:$ROOT_PASSWORD" | pct exec "$CT_ID" -- chpasswd 2>/dev/null || true

    # 6. Start container
    if [ "$START_ON_CREATION" = true ]; then
        echo "-> Starting LXC $CT_ID..."
        pct start "$CT_ID"
    fi

    echo "[DONE] Container $CT_NAME ($CT_ID) deployed successfully."
done

echo "--------------------------------------------------------"
echo "All LXC containers deployed."