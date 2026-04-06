# Backup and Restore Runbook

## Overview
- Backups capture app data dirs and exported Docker named volumes.
- Restores rehydrate bind mounts and volumes, then bring containers up.
- Works for local (LAN) and remote (VPN-only) setups.

## Prerequisites
- restic installed on the machine performing backup/restore.
- Environment configured with:
  - `RESTIC_REPOSITORY` (e.g., `s3:s3.amazonaws.com/lapinel-home-server-backup`)
  - `RESTIC_PASSWORD`
  - `AWS_REGION` (e.g., `us-east-2`)
- Remote EC2: `/etc/home-server/.env` should contain the above.
 - For remote bootstrap (creating `/etc/home-server/.env`, deploy, and WireGuard setup), see `docs/bootstrap.md`.

## Back up
- From repo root: `./backup.sh`
- What it includes:
  - Bind mounts: `vikunja-files`, `vikunja-db`, `actual-data`, `donetick-data`, `donetick-config`, `site`
  - Optional (if present): `homeassistant/config`, `$HOME/.wg-easy`, `$HOME/adguard/{work,conf}`
  - Named volumes exported to tarballs: `caddy_data`, `caddy_config`, `grav_site`
- Prunes snapshots: keep daily 7, weekly 4, monthly 6.

## Restore
- From repo root: `./restore.sh [latest|<snapshot-id>]`
- Steps performed:
  - Stops containers, restores bind mounts, rehydrates named volumes, starts containers.
  - On remote, if `/etc/home-server/.env` and `docker-compose.remote.yml` exist, uses them.

## Choosing a snapshot
- List snapshots: `restic snapshots`
- Inspect a snapshot: `restic ls <snapshot-id>`

## Switching local ↔ remote
- Local → Remote
  - Ensure a fresh backup on local: `./backup.sh`.
  - Deploy EC2 via CDK (VPN-only): see `infra/cdk/README.md`.
  - Start SSM session to EC2 and run `./restore.sh` on the instance in `/opt/home-server`.
- Remote → Local
  - Ensure a fresh backup on remote: SSH/SSM then `./backup.sh`.
  - On your local server’s repo root: `./restore.sh`.

## SSM access (remote)
- Start a session: `aws ssm start-session --target <InstanceId>`
- Change to repo dir: `cd /opt/home-server`
- Ensure env: `cat /etc/home-server/.env`
- Run restore: `./restore.sh`

## Troubleshooting
- restic repo not initialized: `restic init` (first-time only).
- Missing credentials: export `RESTIC_*` env or ensure `/etc/home-server/.env` is present.
- Permission errors on volumes: run as a user with Docker access; script uses a helper container to inject data into volumes.
- Services not up after restore: `docker compose ps` and check logs `docker compose logs -f <service>`.
