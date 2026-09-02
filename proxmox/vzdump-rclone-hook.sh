#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
RCLONE_REMOTE="remote-storage"           # Name configured in `rclone config`
REMOTE_BUCKET="proxmox-backups/vzdump"   # Remote destination directory/bucket
BANDWIDTH_LIMIT="20M"                    # Set upload limit (e.g. 20M, 50M, 0 for unlimited)
MAX_RETRIES=3

PHASE="$1"

# ==============================================================================
# Execution Logic
# ==============================================================================
case "$PHASE" in
    job-start)
        echo "[vzdump-hook] Backup job starting..."
        ;;

    job-init)
        # Runs before each individual VM/CT backup begins
        ;;

    backup-start)
        # Backup engine initialized
        ;;

    backup-abort)
        echo "[vzdump-hook] Backup aborted for guest $2!" >&2
        ;;

    backup-end)
        # Triggered immediately after a single guest backup finishes writing to disk
        # $TARFILE: Full path to the .tar.zst / .vma.zst archive
        # $LOGFILE: Full path to the backup log
        
        GUEST_ID="$2"
        echo "[vzdump-hook] Backup created for guest $GUEST_ID: $TARFILE"

        if [[ -f "$TARFILE" ]]; then
            echo "[vzdump-hook] Uploading archive to ${RCLONE_REMOTE}:${REMOTE_BUCKET}/..."
            rclone copy "$TARFILE" "${RCLONE_REMOTE}:${REMOTE_BUCKET}" \
                --bwlimit "$BANDWIDTH_LIMIT" \
                --retries "$MAX_RETRIES" \
                --low-level-retries 10 \
                --stats 30s \
                --fast-list

            # Optional: Upload the accompanying log file
            if [[ -n "${LOGFILE:-}" && -f "$LOGFILE" ]]; then
                rclone copy "$LOGFILE" "${RCLONE_REMOTE}:${REMOTE_BUCKET}" --quiet
            fi

            echo "[vzdump-hook] Successfully uploaded $TARFILE to offsite storage."
        fi
        ;;

    job-end)
        # Runs once after all VM/CT backups in the batch job are finished
        echo "[vzdump-hook] All local backups finished."
        
        # Optional: Prune offsite cloud files older than 30 days
        echo "[vzdump-hook] Pruning remote backups older than 30 days..."
        rclone delete "${RCLONE_REMOTE}:${REMOTE_BUCKET}" \
            --min-age 30d \
            --include "vzdump-*" \
            --rmdirs || true

        echo "[vzdump-hook] Offsite cleanup complete."
        ;;

    *)
        echo "[vzdump-hook] Unknown phase '$PHASE'" >&2
        ;;
esac

exit 0