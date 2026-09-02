#!/usr/bin/env bash
set -euo pipefail

TEMPLATE_ID=8000
CT_ID=403
CT_NAME="mon-prometheus-grafana"
STORAGE="local-lvm"
DISK_SIZE="50G"
CORES=2
MEMORY=2048
IP_ADDR="192.168.1.103/24"
GW="192.168.1.1"

CLEAN_IP="${IP_ADDR%/*}"

# ==============================================================================
# Pre-checks
# ==============================================================================
if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] This script must run as root on the Proxmox host." >&2
   exit 1
fi

if pct status "$CT_ID" &>/dev/null; then
    echo "[ERROR] Container $CT_ID already exists. Destroy it first with: pct destroy $CT_ID" >&2
    exit 1
fi

# ==============================================================================
# 1. Provision Container
# ==============================================================================
echo "[1/5] Cloning Container $CT_ID from Template $TEMPLATE_ID..."
pct clone "$TEMPLATE_ID" "$CT_ID" --hostname "$CT_NAME" --full 1

echo "[2/5] Applying specs and networking..."
pct set "$CT_ID" \
    --cores "$CORES" \
    --memory "$MEMORY" \
    --swap 512 \
    --net0 name=eth0,bridge=vmbr0,ip="$IP_ADDR",gw="$GW" \
    --onboot 1

pct resize "$CT_ID" rootfs "$DISK_SIZE"

echo "[3/5] Starting Container..."
pct start "$CT_ID"
sleep 4

# ==============================================================================
# 2. Install Latest Prometheus & Node Exporter via Official Binaries
# ==============================================================================
echo "[4/5] Installing dependencies and latest Prometheus & Grafana..."
pct exec "$CT_ID" -- apt update
pct exec "$CT_ID" -- apt install -y curl wget tar apt-transport-https gpg

# Create dedicated prometheus system user and directories
pct exec "$CT_ID" -- bash -c "
    id -u prometheus &>/dev/null || useradd --no-create-home --shell /bin/false prometheus
    mkdir -p /etc/prometheus /var/lib/prometheus
    chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus
"

# Fetch latest Prometheus release tag from GitHub API and install binaries
pct exec "$CT_ID" -- bash -c '
    PROM_VERSION=$(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | grep tag_name | cut -d '"'"'"'"' -f 4 | sed "s/^v//")
    echo "Downloading Prometheus v${PROM_VERSION}..."
    curl -fsSL -o /tmp/prometheus.tar.gz "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
    tar -xzf /tmp/prometheus.tar.gz -C /tmp
    
    cp /tmp/prometheus-${PROM_VERSION}.linux-amd64/prometheus /usr/local/bin/
    cp /tmp/prometheus-${PROM_VERSION}.linux-amd64/promtool /usr/local/bin/
    chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool

    # Copy baseline consoles and config if missing
    cp -r /tmp/prometheus-${PROM_VERSION}.linux-amd64/consoles /etc/prometheus
    cp -r /tmp/prometheus-${PROM_VERSION}.linux-amd64/console_libraries /etc/prometheus
    if [ ! -f /etc/prometheus/prometheus.yml ]; then
        cp /tmp/prometheus-${PROM_VERSION}.linux-amd64/prometheus.yml /etc/prometheus/
    fi
    chown -R prometheus:prometheus /etc/prometheus

    rm -rf /tmp/prometheus*
'

# Create Prometheus Systemd Service
pct exec "$CT_ID" -- bash -c "cat << 'EOF' > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus Time Series Collection and Server
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \\
    --config.file=/etc/prometheus/prometheus.yml \\
    --storage.tsdb.path=/var/lib/prometheus/ \\
    --web.console.templates=/etc/prometheus/consoles \\
    --web.console.libraries=/etc/prometheus/console_libraries \\
    --web.listen-address=0.0.0.0:9090 \\
    --storage.tsdb.retention.time=30d
Restart=always

[Install]
WantedBy=multi-user.target
EOF"

# ==============================================================================
# 3. Install Latest Grafana (Official APT Repository)
# ==============================================================================
pct exec "$CT_ID" -- bash -c "
    mkdir -p /etc/apt/keyrings/
    curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/grafana.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main' > /etc/apt/sources.list.d/grafana.list
    apt update && apt install -y grafana
"

# ==============================================================================
# 4. Enable and Start Services
# ==============================================================================
echo "[5/5] Reloading and starting services..."
pct exec "$CT_ID" -- systemctl daemon-reload
pct exec "$CT_ID" -- systemctl enable --now prometheus grafana-server

echo "========================================================================"
echo "=== Monitoring Stack Deployed Successfully! ==="
echo "Grafana    : http://${CLEAN_IP}:3000 (Default: admin / admin)"
echo "Prometheus : http://${CLEAN_IP}:9090"
echo "========================================================================"