#!/bin/bash
set -euo pipefail

# Source env if running as cron (vars may not be in environment)
if [ -f /etc/home-server/.env ]; then
  set -a; source /etc/home-server/.env; set +a
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

# On EC2 app data lives on a separate persistent volume; locally it's relative to the repo
if [ -d /opt/home-server-data ]; then
  DATA_BASE=/opt/home-server-data
else
  DATA_BASE=$SCRIPT_DIR
fi

echo "[backup] Starting at $(date -Is)"
echo "[backup] Data base: $DATA_BASE"

# Paths to include — skip anything tracked in git or regeneratable (e.g. TLS certs)
CANDIDATE_PATHS=(
  "$DATA_BASE/actual-data"
  "$DATA_BASE/vikunja-files"
  "$DATA_BASE/vikunja-db"
  "$DATA_BASE/donetick-data"
  "$HOME/.wg-easy"
)

# Optional local-only paths (present on local server, skipped on EC2)
OPTIONAL_PATHS=(
  "$SCRIPT_DIR/homeassistant/config"
  "$HOME/adguard/work"
  "$HOME/adguard/conf"
)

DATA_PATHS=()
for p in "${CANDIDATE_PATHS[@]}" "${OPTIONAL_PATHS[@]}"; do
  if [ -d "$p" ]; then
    DATA_PATHS+=("$p")
  else
    echo "[backup] Skipping $p (not found)"
  fi
done

if [ ${#DATA_PATHS[@]} -eq 0 ]; then
  echo "[backup] No data paths found — nothing to back up"
  exit 1
fi

# Export grav_site Docker volume if present
TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

if command -v docker >/dev/null 2>&1; then
  if docker volume inspect grav_site >/dev/null 2>&1; then
    echo "[backup] Exporting grav_site volume..."
    docker run --rm \
      -v "grav_site:/data:ro" \
      -v "$TMP_DIR:/backup" \
      alpine:3 sh -c "cd /data && tar czf /backup/vol-grav_site.tar.gz ."
    DATA_PATHS+=("$TMP_DIR")
  fi
fi

echo "[backup] Paths: ${DATA_PATHS[*]}"
restic backup "${DATA_PATHS[@]}"

echo "[backup] Pruning old snapshots..."
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune

echo "[backup] Done at $(date -Is)"
