#!/usr/bin/env bash
set -euo pipefail

CT_ID=402
CT_NAME="net-dns-pihole"
STORAGE="local-lvm"
DISK_SIZE="8G"
CORES=1
MEMORY=1024
IP_ADDR="192.168.1.102/24"
GW="192.168.1.1"

echo "[1/4] Creating Container $CT_ID..."
pct create "$CT_ID" local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
    --hostname "$CT_NAME" \
    --cores "$CORES" --memory "$MEMORY" --swap 256 \
    --rootfs "$STORAGE:$DISK_SIZE" \
    --net0 name=eth0,bridge=vmbr0,ip="$IP_ADDR",gw="$GW" \
    --unprivileged 1 \
    --features nesting=1 \
    --onboot 1

echo "[2/4] Starting Container..."
pct start "$CT_ID"
sleep 5

echo "[3/4] Running automated Pi-hole setup..."
pct exec "$CT_ID" -- apt update
pct exec "$CT_ID" -- apt install -y curl ufw sudo

# Preconfigure unattended Pi-hole install
pct exec "$CT_ID" -- mkdir -p /etc/pihole
pct exec "$CT_ID" -- bash -c "cat << 'EOF' > /etc/pihole/setupVars.conf
PIHOLE_INTERFACE=eth0
IPV4_ADDRESS=$IP_ADDR
PIHOLE_DNS_1=1.1.1.1
PIHOLE_DNS_2=8.8.8.8
QUERY_LOGGING=true
INSTALL_WEB_SERVER=true
INSTALL_WEB_INTERFACE=true
LIGHTTPD_ENABLED=true
EOF"

pct exec "$CT_ID" -- bash -c "curl -sSL https://install.pi-hole.net | bash --unattended"
pct exec "$CT_ID" -- pihole -a -p "AdminPass123"

echo "=== Pi-hole DNS LXC ready at http://${IP_ADDR%/*}/admin (Password: AdminPass123) ==="