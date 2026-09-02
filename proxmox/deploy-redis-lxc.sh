#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
CT_ID=406
CT_NAME="cache-redis-standalone"
STORAGE_POOL="local-lvm"          # e.g., local-lvm, local-zfs
DISK_SIZE="8G"
CORES=2
MEMORY=1024                       # in MB (adjust based on expected key set size)
SWAP=512
BRIDGE="vmbr0"
IP_ADDR="192.168.1.106/24"
GATEWAY="192.168.1.1"
NAMESERVER="1.1.1.1"
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"

# Redis Configuration
REDIS_MAXMEMORY="768mb"           # Recommended: ~75% of container RAM
REDIS_MAXMEMORY_POLICY="allkeys-lru" # Options: noeviction, allkeys-lru, volatile-lru
REDIS_PASSWORD="ChangeMeInProdRedisPass123!" # Leave empty ("") if using network-isolated ACLs

# ==============================================================================
# Pre-checks
# ==============================================================================
if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] This script must run as root on the Proxmox host." >&2
   exit 1
fi

if pct status "$CT_ID" &>/dev/null; then
    echo "[ERROR] Container ID $CT_ID already exists." >&2
    exit 1
fi

# ==============================================================================
# Step 1: Host-Level Kernel Optimizations for Redis
# (vm.overcommit_memory and somaxconn are host-wide kernel knobs)
# ==============================================================================
echo "[1/5] Applying host-level kernel optimizations for Redis..."

# 1. Overcommit memory: Prevents BGSAVE fork failures under heavy writes
sysctl vm.overcommit_memory=1 >/dev/null
if ! grep -q "vm.overcommit_memory" /etc/sysctl.d/99-redis.conf 2>/dev/null; then
    echo "vm.overcommit_memory = 1" >> /etc/sysctl.d/99-redis.conf
fi

# 2. TCP Backlog: Prevents slow connection warnings
sysctl net.core.somaxconn=1024 >/dev/null
if ! grep -q "net.core.somaxconn" /etc/sysctl.d/99-redis.conf 2>/dev/null; then
    echo "net.core.somaxconn = 1024" >> /etc/sysctl.d/99-redis.conf
fi

# 3. Disable Transparent Huge Pages (THP) on host runtime
if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
    echo never > /sys/kernel/mm/transparent_hugepage/enabled
fi

# ==============================================================================
# Step 2: Create LXC Container
# ==============================================================================
echo "[2/5] Creating unprivileged LXC container $CT_ID..."
pct create "$CT_ID" "local:vztmpl/$TEMPLATE" \
    --hostname "$CT_NAME" \
    --cores "$CORES" \
    --memory "$MEMORY" \
    --swap "$SWAP" \
    --rootfs "$STORAGE_POOL:$DISK_SIZE" \
    --net0 "name=eth0,bridge=$BRIDGE,ip=$IP_ADDR,gw=$GATEWAY" \
    --nameserver "$NAMESERVER" \
    --unprivileged 1 \
    --features nesting=1 \
    --onboot 1

# ==============================================================================
# Step 3: Start and Install Redis
# ==============================================================================
echo "[3/5] Starting container and installing Redis..."
pct start "$CT_ID"
sleep 5

pct exec "$CT_ID" -- apt update
pct exec "$CT_ID" -- apt install -y redis-server curl

# ==============================================================================
# Step 4: Tune Redis Configuration Inside LXC
# ==============================================================================
echo "[4/5] Applying memory ceilings and network binds..."
REDIS_CONF="/etc/redis/redis.conf"

# Bind to all interfaces (protected mode will handle safety if password is set)
pct exec "$CT_ID" -- sed -i "s/^bind 127.0.0.1/bind 0.0.0.0/g" "$REDIS_CONF"

# Set TCP backlog to match host setting
pct exec "$CT_ID" -- sed -i "s/^tcp-backlog 511/tcp-backlog 1024/g" "$REDIS_CONF"

# Enforce maxmemory ceiling to avoid triggering Proxmox host/LXC OOM killer
pct exec "$CT_ID" -- sed -i "s/^# maxmemory <bytes>/maxmemory $REDIS_MAXMEMORY/g" "$REDIS_CONF"
pct exec "$CT_ID" -- sed -i "s/^# maxmemory-policy noeviction/maxmemory-policy $REDIS_MAXMEMORY_POLICY/g" "$REDIS_CONF"

# Set requirepass if specified
if [[ -n "$REDIS_PASSWORD" ]]; then
    pct exec "$CT_ID" -- sed -i "s/^# requirepass foobared/requirepass $REDIS_PASSWORD/g" "$REDIS_CONF"
fi

# Enable AOF (Append Only File) for better data durability alongside RDB
pct exec "$CT_ID" -- sed -i "s/^appendonly no/appendonly yes/g" "$REDIS_CONF"

# ==============================================================================
# Step 5: Restart & Verify
# ==============================================================================
echo "[5/5] Restarting Redis and verifying status..."
pct exec "$CT_ID" -- systemctl restart redis-server

CLEAN_IP="${IP_ADDR%/*}"
echo "--------------------------------------------------------"
echo "=== Redis LXC Deployed Successfully! ==="
echo "Container ID : $CT_ID"
echo "Host Address : $CLEAN_IP:6379"
echo "Memory Cap   : $REDIS_MAXMEMORY (Eviction: $REDIS_MAXMEMORY_POLICY)"
echo "Password     : ${REDIS_PASSWORD:-[None Configured]}"
echo "Test ping via host: pct exec $CT_ID -- redis-cli $([ -n "$REDIS_PASSWORD" ] && echo "-a $REDIS_PASSWORD") ping"
echo "--------------------------------------------------------"