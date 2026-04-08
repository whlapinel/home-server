#!/bin/bash
set -euo pipefail

# Restore Actual Budget data from a restic snapshot.
# Usage: ./restore-actual.sh [snapshot-id|latest]
# Must be run from /opt/home-server on the EC2 instance.

SNAPSHOT="${1:-latest}"

if [ -f /etc/home-server/.env ]; then
  set -a; source /etc/home-server/.env; set +a
fi

cd "$(dirname "$0")"

DATA_BASE=/opt/home-server-data

echo "[restore-actual] Stopping actual_server..."
docker compose -f docker-compose.yml -f docker-compose.remote.yml stop actual_server

echo "[restore-actual] Restoring actual-data from snapshot: $SNAPSHOT"
restic restore "$SNAPSHOT" \
  --target / \
  --include "${DATA_BASE}/actual-data"

echo "[restore-actual] Starting actual_server..."
docker compose -f docker-compose.yml -f docker-compose.remote.yml start actual_server

echo "[restore-actual] Done."
