#! /bin/bash

set -euo pipefail

# Usage: ./restore.sh [snapshot-id|latest]
# Requires restic env vars set (RESTIC_REPOSITORY, RESTIC_PASSWORD, AWS_REGION if S3)

SNAPSHOT="${1:-latest}"

command -v restic >/dev/null 2>&1 || { echo "restic not found in PATH" >&2; exit 1; }

REPO_ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$REPO_ROOT"

echo "Stopping containers (if any) to restore data safely..."
if [ -f docker-compose.yml ]; then
  if docker compose ls >/dev/null 2>&1; then
    docker compose down || true
  fi
fi

STAGING=$(mktemp -d)
cleanup() { rm -rf "$STAGING"; }
trap cleanup EXIT

echo "Restoring snapshot '$SNAPSHOT' into staging: $STAGING"
restic restore "$SNAPSHOT" --target "$STAGING"

# Helper to sync a directory from staging to target
sync_dir() {
  local name="$1"   # e.g., vikunja-files or homeassistant/config
  local dest="$2"   # e.g., ./vikunja-files

  # Try direct path first
  local src=""
  if [ -d "$STAGING/$name" ]; then
    src="$STAGING/$name"
  else
    # Fallback: search by basename
    local base
    base=$(basename "$name")
    src=$(find "$STAGING" -type d -name "$base" | head -n1 || true)
  fi

  if [ -z "$src" ]; then
    echo "[skip] Could not find '$name' in staging"
    return
  fi

  echo "Syncing $src -> $dest"
  mkdir -p "$dest"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$src"/ "$dest"/
  else
    # cp -a may leave stale files; clean dest first
    find "$dest" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    cp -a "$src"/. "$dest"/
  fi
}

echo "Restoring bind-mounted data..."
sync_dir "vikunja-files" "./vikunja-files"
sync_dir "vikunja-db" "./vikunja-db"
sync_dir "actual-data" "./actual-data"
sync_dir "donetick-data" "./donetick-data"
sync_dir "donetick-config" "./donetick-config"
sync_dir "site" "./site"

# Optional local-only paths
sync_dir "homeassistant/config" "./homeassistant/config"
sync_dir ".wg-easy" "$HOME/.wg-easy"
sync_dir "work" "$HOME/adguard/work"
sync_dir "conf" "$HOME/adguard/conf"

echo "Rehydrating named Docker volumes (if tarballs present)..."
mapfile -t TARBALLS < <(find "$STAGING" -type f -name 'vol-*.tar.gz' 2>/dev/null || true)
for tb in "${TARBALLS[@]:-}"; do
  [ -n "$tb" ] || continue
  bname=$(basename "$tb")
  # Expect format vol-<volume>-YYYYmmddHHMMSS.tar.gz
  vol=$(echo "$bname" | sed -E 's/^vol-([^.-]+)-[0-9]{8,14}\.tar\.gz$/\1/')
  if [ -z "$vol" ] || [ "$vol" = "$bname" ]; then
    echo "[skip] Could not parse volume name from $bname"
    continue
  fi
  echo "Restoring Docker volume: $vol from $bname"
  docker volume inspect "$vol" >/dev/null 2>&1 || docker volume create "$vol" >/dev/null
  docker run --rm -v "$vol:/data" -v "$(dirname "$tb"):/backup" alpine:3 sh -lc "cd /data && rm -rf ./* && tar xzf /backup/$bname"
done

echo "Starting containers..."
if [ -f docker-compose.yml ]; then
  if [ -f docker-compose.remote.yml ] && [ -f /etc/home-server/.env ]; then
    docker compose -f docker-compose.yml -f docker-compose.remote.yml --env-file /etc/home-server/.env up -d
  else
    docker compose up -d
  fi
fi

echo "Restore completed."

