#!/usr/bin/env bash
set -euo pipefail

TEMPLATE_ID=8000
CT_ID=401
CT_NAME="db-postgres-redis"
DISK_SIZE="16G"
CORES=2
MEMORY=2048
IP_ADDR="192.168.1.101/24"
GW="192.168.1.1"

echo "[1/4] Cloning Container $CT_ID from Template $TEMPLATE_ID..."
pct clone "$TEMPLATE_ID" "$CT_ID" --hostname "$CT_NAME" --full 1

echo "[2/4] Applying specs and networking..."
pct set "$CT_ID" \
    --cores "$CORES" \
    --memory "$MEMORY" \
    --swap 512 \
    --net0 name=eth0,bridge=vmbr0,ip="$IP_ADDR",gw="$GW" \
    --onboot 1

pct resize "$CT_ID" rootfs "$DISK_SIZE"

echo "[3/4] Starting Container..."
pct start "$CT_ID"
sleep 4

echo "[4/4] Adding official PostgreSQL + Redis APT repos and installing latest versions..."

pct exec "$CT_ID" -- bash -c "
    apt update && apt install -y curl ca-certificates lsb-release gnupg

    # 1. Official PostgreSQL (PGDG) Repository
    install -d /etc/apt/keyrings
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor --yes -o /etc/apt/keyrings/postgresql.gpg
    echo \"deb [signed-by=/etc/apt/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt \$(lsb_release -cs)-pgdg main\" > /etc/apt/sources.list.d/pgdg.list

    # 2. Official Redis Repository
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor --yes -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo \"deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb \$(lsb_release -cs) main\" > /etc/apt/sources.list.d/redis.list

    # 3. Update index and install the latest versions
    apt update
    apt install -y postgresql postgresql-contrib redis
"

echo "Configuring network listeners and authentication..."
# Locate whichever major PostgreSQL version was installed
pct exec "$CT_ID" -- bash -c "sed -i \"s/#listen_addresses = 'localhost'/listen_addresses = '*'/g\" /etc/postgresql/*/main/postgresql.conf"
pct exec "$CT_ID" -- bash -c "echo 'host all all 0.0.0.0/0 md5' >> /etc/postgresql/*/main/pg_hba.conf"

# Configure latest Redis listener
pct exec "$CT_ID" -- sed -i "s/^bind 127.0.0.1/bind 0.0.0.0/g" /etc/redis/redis.conf

# Restart services
pct exec "$CT_ID" -- systemctl restart postgresql redis-server

echo "=== Database container deployed and listening on $IP_ADDR! ==="