# Remote-Ready Home Server Plan

Last updated: INITIAL DRAFT

## Goals
- Single repo runs on local or remote EC2 with easy switching.
- Reproducible, low-friction deploys; safe secret handling; quick rollback.
- t3.micro-friendly footprint; minimal infra and cost.

## Current Repo Summary
- Reverse proxy: Caddy with internal TLS and `*.lapinel-home.arpa`.
- Services (Docker Compose):
  - homeassistant (host network)
  - grav
  - caddy (ports 80/443)
  - adguardhome (DNS on 53)
  - wg-easy (WireGuard)
  - vikunja, donetick, actual_server
- Caddy reverse proxies to LAN IP `192.168.86.234:*` (not container names).
- Volumes: mix of relative paths and `~` home-paths (not portable to EC2).
- `.env` referenced (good); not in repo.
- Note: `donetick` mounts `./doneticket-config` but repo only shows `donetick-data` (likely a path typo to confirm later).

## Configuration Strategy
- Compose files and profiles:
  - Base: `docker-compose.yml` – core services; internal networking; named volumes.
  - Local: `docker-compose.local.yml` – enable HA/AdGuard/WG; internal TLS; port mappings for convenience.
  - Remote: `docker-compose.remote.yml` – exclude HA/AdGuard by default; memory limits; expose only 80/443 via Caddy; optional WG.
- Switching commands:
  - Local: `docker compose -f docker-compose.yml -f docker-compose.local.yml --env-file .env.local up -d`
  - Remote (on EC2): `docker compose -f docker-compose.yml -f docker-compose.remote.yml --env-file /etc/home-server/.env up -d`
- App config/env:
  - `.env.local` (gitignored) for local; `.env.remote` (SOPS or SSM-managed) for remote.

## Caddy Strategy
- Replace LAN IP upstreams with Docker service names: e.g., `reverse_proxy vikunja:3456`, `donetick:2021`, `actual_server:5006`, `grav:80`.
- Separate hostnames per environment:
  - Local: `*.lapinel-home.arpa` with `tls internal`.
  - Remote: real domain with Let’s Encrypt (`{$DOMAIN}`, `{$EMAIL}` via env).
- Implement either two Caddyfiles (`Caddyfile.local`, `Caddyfile.remote`) or a single env-templated file.

## Secrets
- Local: `.env.local` (gitignored).
- Remote: choose one
  - AWS SSM Parameter Store (preferred on EC2 with IAM role); render `/etc/home-server/.env` during deploy.
  - SOPS-encrypted `.env.remote` in repo (decrypt in CI or on host).

## AWS EC2 Setup
- Instance: t3.micro (2 vCPU burst, 1 GiB RAM).
- Storage: 20–40 GiB EBS; enable 1–2 GiB swap.
- Security Group: allow 22 (restricted to your IP), 80/443; avoid opening 53 unless strictly necessary and IP-restricted.
- Bootstrap (cloud-init): install Docker, add user, ufw, fail2ban, swap; optional SSM agent + IAM role (for SSM/SSM Parameter Store and backups).

## Deployment Automation
- Simple approach: `deploy.sh` uses SSH (or SSM) to:
  - Ensure repo exists at `/opt/home-server`.
  - Write `/etc/home-server/.env` (from SSM or provided file).
  - Run compose with `docker-compose.remote.yml`.
- Optional CI (GitHub Actions): build images or just rsync/SSH and run compose on push/tag.

## Backups
- Use restic to S3 with encryption; daily backup + prune.
- Target named volumes and bind-mounted data dirs, not the whole `/var/lib/docker/volumes`.
- Document restore steps and test.

## Networking & Security
- Public domain + DNS to Elastic IP for selected apps.
- Let’s Encrypt on remote; internal TLS on local.
- Consider Cloudflare Tunnel if avoiding open 80/443.
- Keep AdGuard local; serving public DNS on 53 is risky.
- Expose only apps intended for public; add auth if needed.

## Barriers & Mitigations
- LAN-only dependencies (Home Assistant): keep local or bridge via Tailscale/WireGuard routed subnets to home.
- Public DNS (AdGuard): keep local; if remote, restrict by SG and bind to private interfaces.
- Upstreams to LAN IP: replace with Docker service names.
- t3.micro memory: set compose memory limits, add swap, keep remote stack minimal.
- `~` host-paths: replace with named volumes or repo-relative paths for portability.

## Planned Repo Changes (Diff Outline)
1) Add `docker-compose.local.yml` and `docker-compose.remote.yml` with profiles, memory limits, and service selection.
2) Update base `docker-compose.yml` to use named volumes, internal networking, and remove non-essential host port mappings.
3) Update Caddy config: service-name upstreams; split local vs remote hostnames/certs.
4) Add `env/.env.example`, `.env.local`, and a template/SSM mapping for `.env.remote`.
5) Add `deploy/bootstrap-ec2.sh`, `deploy/deploy.sh`, and `deploy/cloud-init.yaml`.
6) Update `backup.sh` to parameterize restic env, scope to app data, and include prune.
7) Add `docs/deploy.md` with runbooks and checklists.

## Decisions Needed
- Remote domain and subdomains (e.g., `example.com`, `tasks.example.com`, etc.).
- Which services are public vs VPN-only on remote.
- Run WireGuard on EC2? (Alternative: keep VPN on home server and peer EC2.)
- Secrets method: AWS SSM or SOPS.
- Backups: S3 bucket/region and retention policy.

## Deployment Checklist (Remote)
1) Provision EC2 t3.micro; attach Elastic IP; set SG for 22 (your IP), 80/443.
2) Apply cloud-init: Docker, user, swap, ufw/fail2ban, SSM (optional).
3) Configure DNS for subdomains to Elastic IP.
4) Populate remote secrets (`/etc/home-server/.env` via SSM or file).
5) Deploy: `docker compose -f docker-compose.yml -f docker-compose.remote.yml --env-file /etc/home-server/.env up -d`.
6) Verify Caddy certs and app routes.
7) Enable and test restic backups to S3; document restore.

## Status & Next Steps
- Status: Planning captured; awaiting decisions above.
- Next: Implement compose overrides, Caddy changes, deploy scripts, and docs once decisions are provided.

