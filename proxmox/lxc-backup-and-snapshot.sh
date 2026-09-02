#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
# Define target LXC container IDs (space-separated)
CONTAINER_IDS=(401 402 403 404 405 406)

# Backup storage target (defined in Proxmox Storage: e.g., 'local', 'backup-nfs', 'pbs')
BACKUP_STORAGE="local"

# Compression algorithm (zstd is multi-threaded and fastest)
COMPRESSION="zstd"

# VZDump Backup Mode:
# - 'snapshot': Zero downtime, non-blocking copy (preferred for LXC)
# - 'suspend': Briefly freezes container to flush memory/dirty pages
# - 'stop': Clean shutdown, backup, restart (highest consistency for databases)
BACKUP_MODE="snapshot"

# Retention Policies
KEEP_DAILY_SNAPSHOTS=7    # Number of rolling local storage snapshots to retain
KEEP_BACKUP_COPIES=3      # Number of full VZDump backup archives to retain per CT

# ==============================================================================
# Pre-flight Checks
# ==============================================================================
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] This script must be run as root on the Proxmox host." >&2
    exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SNAPSHOT_NAME="auto_${TIMESTAMP}"

echo "========================================================"
echo "Starting LXC Backup & Snapshot Run: $(date)"
echo "Target Containers: ${CONTAINER_IDS[*]}"
echo "========================================================"

# ==============================================================================
# Step 1: Local Copy-on-Write Snapshots (with Retention Rotation)
# ==============================================================================
echo ""
echo "--- Step 1: Generating Local Snapshots ---"

for CT_ID in "${CONTAINER_IDS[@]}"; do
    if ! pct status "$CT_ID" &>/dev/null; then
        echo "[SKIP] CT $CT_ID does not exist on this node. Skipping."
        continue
    fi

    echo "-> Creating snapshot '$SNAPSHOT_NAME' for CT $CT_ID..."
    pct snapshot "$CT_ID" "$SNAPSHOT_NAME" \
        --description "Automated script snapshot taken at $(date)"

    # Prune older automated snapshots beyond retention limit
    AUTO_SNAPS=$(pct listsnapshot "$CT_ID" | awk '{print $1}' | grep '^auto_' || true)
    SNAP_COUNT=$(echo "$AUTO_SNAPS" | sed '/^$/d' | wc -l)

    if (( SNAP_COUNT > KEEP_DAILY_SNAPSHOTS )); then
        PRUNE_COUNT=$(( SNAP_COUNT - KEEP_DAILY_SNAPSHOTS ))
        SNAPS_TO_DELETE=$(echo "$AUTO_SNAPS" | head -n "$PRUNE_COUNT")

        for SNAP in $SNAPS_TO_DELETE; do
            echo "   [PRUNE] Removing old snapshot: $SNAP on CT $CT_ID..."
            pct delsnapshot "$CT_ID" "$SNAP"
        done
    fi
done

# ==============================================================================
# Step 2: Full Compressed VZDump Backups
# ==============================================================================
echo ""
echo "--- Step 2: Running VZDump Standalone Backups ---"

# Build comma-separated list of active containers
VALID_CTS=()
for CT_ID in "${CONTAINER_IDS[@]}"; do
    if pct status "$CT_ID" &>/dev/null; then
        VALID_CTS+=("$CT_ID")
    fi
done

CT_CSV=$(IFS=,; echo "${VALID_CTS[*]}")

if [[ -n "$CT_CSV" ]]; then
    echo "Running vzdump for CT IDs: $CT_CSV..."
    vzdump "$CT_CSV" \
        --storage "$BACKUP_STORAGE" \
        --mode "$BACKUP_MODE" \
        --compress "$COMPRESSION" \
        --prune-backups "keep-last=$KEEP_BACKUP_COPIES" \
        --quiet 0 \
        --notes-template "Automated daily backup of {{guestname}}"
else
    echo "[WARN] No active containers found to back up."
fi

echo ""
echo "========================================================"
echo "Backup & Snapshot Run Complete: $(date)"
echo "========================================================"