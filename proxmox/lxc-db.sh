#!/usr/bin/env bash
set -euo pipefail

CT_ID=401
CT_NAME="db-postgres-redis"
STORAGE="local-lvm"
DISK_SIZE="16G"
CORES=2
MEMORY=2048
IP_ADDR="192.168.1.101/24"
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

echo "[3/4] Installing PostgreSQL and Redis..."
pct exec "$CT_ID" -- apt update
pct exec "$CT_ID" -- apt install -y postgresql postgresql-contrib redis-server curl

echo "[4/4] Enabling external network listeners..."
# Allow PostgreSQL to listen on all local interfaces
pct exec "$CT_ID" -- sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /etc/postgresql/16/main/postgresql.conf
echo "host all all 0.0.0.0/0 md5" | pct exec "$CT_ID" -- tee -a /etc/postgresql/16/main/pg_hba.conf

# Allow Redis to listen on all interfaces (protected mode enabled by default)
pct exec "$CT_ID" -- sed -i "s/^bind 127.0.0.1/bind 0.0.0.0/g" /etc/redis/redis.conf

pct exec "$CT_ID" -- systemctl restart postgresql redis-server
echo "=== Database LXC ready at $IP_ADDR (Postgres: 5432, Redis: 6379) ==="