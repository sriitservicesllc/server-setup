#!/usr/bin/env bash
set -euo pipefail

CT_ID=404
CT_NAME="dev-gitea"
STORAGE="local-lvm"
DISK_SIZE="15G"
CORES=2
MEMORY=1024
IP_ADDR="192.168.1.104/24"
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

echo "[3/4] Installing Git and Downloading Gitea..."
pct exec "$CT_ID" -- apt update
pct exec "$CT_ID" -- apt install -y git sqlite3 curl

pct exec "$CT_ID" -- adduser --system --shell /bin/bash --gecos 'Git Version Control' --group --disabled-password --home /home/git git
pct exec "$CT_ID" -- curl -Lo /usr/local/bin/gitea https://dl.gitea.com/gitea/1.22.0/gitea-1.22.0-linux-amd64
pct exec "$CT_ID" -- chmod +x /usr/local/bin/gitea
pct exec "$CT_ID" -- mkdir -p /var/lib/gitea/{custom,data,log} /etc/gitea
pct exec "$CT_ID" -- chown -R git:git /var/lib/gitea /etc/gitea

echo "[4/4] Creating systemd service..."
pct exec "$CT_ID" -- bash -c "cat << 'EOF' > /etc/systemd/system/gitea.service
[Unit]
Description=Gitea (Git with a cup of tea)
After=network.target

[Service]
RestartSec=2s
Type=simple
User=git
Group=git
WorkingDirectory=/var/lib/gitea/
ExecStart=/usr/local/bin/gitea web --config /etc/gitea/app.ini
Restart=always
Environment=USER=git HOME=/home/git GITEA_WORK_DIR=/var/lib/gitea

[Install]
WantedBy=multi-user.target
EOF"

pct exec "$CT_ID" -- systemctl enable --now gitea
echo "=== Gitea LXC ready at http://${IP_ADDR%/*}:3000 ==="