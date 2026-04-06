#! /bin/bash

set -euo pipefail

# Expected env (from .env or instance role + env file):
# - RESTIC_REPOSITORY (e.g., s3:s3.amazonaws.com/bucket-name)
# - RESTIC_PASSWORD
# - AWS_REGION (if using S3)

# Data paths to back up (bind mounts and app data dirs)
DATA_PATHS=(
  "./vikunja-files"
  "./vikunja-db"
  "./actual-data"
  "./donetick-data"
  "./donetick-config"
  "./site"
)

# Include optional local-only paths if present
OPTIONAL_PATHS=(
  "$HOME/.wg-easy"
  "$HOME/adguard/work"
  "$HOME/adguard/conf"
  "./homeassistant/config"
)
for p in "${OPTIONAL_PATHS[@]}"; do
  if [ -d "$p" ]; then
    DATA_PATHS+=("$p")
  fi
done

# Export named Docker volumes to a temp dir for backup (if docker available)
TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

if command -v docker >/dev/null 2>&1; then
  VOLUMES=(caddy_data caddy_config grav_site)
  for vol in "${VOLUMES[@]}"; do
    if docker volume inspect "$vol" >/dev/null 2>&1; then
      echo "Exporting volume $vol..."
      docker run --rm -v "${vol}:/data:ro" -v "$TMP_DIR:/backup" alpine:3 sh -lc "cd /data && tar czf /backup/vol-${vol}-$(date +%Y%m%d%H%M%S).tar.gz ." || true
    fi
  done
fi

echo "Starting restic backup..."
restic backup "${DATA_PATHS[@]}" "$TMP_DIR"

echo "Pruning old snapshots..."
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune

echo "Backup completed."
