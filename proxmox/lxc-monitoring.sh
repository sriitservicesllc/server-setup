#!/usr/bin/env bash
set -euo pipefail

CT_ID=403
CT_NAME="mon-prometheus-grafana"
STORAGE="local-lvm"
DISK_SIZE="20G"
CORES=2
MEMORY=2048
IP_ADDR="192.168.1.103/24"
GW="192.168.1.1"

echo "[1/4] Creating Container $CT_ID..."
pct create "$CT_ID" local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
    --hostname "$CT_NAME" \
    --cores "$CORES" --memory "$MEMORY" --swap 512 \
    --rootfs "$STORAGE:$DISK_SIZE" \
    --net0 name=eth0,bridge=vmbr0,ip="$IP_ADDR",gw="$GW" \
    --unprivileged 1 \
    --onboot 1

echo "[2/4] Starting Container..."
pct start "$CT_ID"
sleep 5

echo "[3/4] Installing Prometheus and Grafana repository..."
pct exec "$CT_ID" -- apt update
pct exec "$CT_ID" -- apt install -y prometheus apt-transport-https software-properties-common wget gpg

pct exec "$CT_ID" -- bash -c "mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor > /etc/apt/keyrings/grafana.gpg
echo 'deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main' > /etc/apt/sources.list.d/grafana.list
apt update && apt install -y grafana"

echo "[4/4] Starting Services..."
pct exec "$CT_ID" -- systemctl enable --now prometheus grafana-server
echo "=== Monitoring LXC ready! Grafana: http://${IP_ADDR%/*}:3000 (admin/admin), Prometheus: http://${IP_ADDR%/*}:9090 ==="