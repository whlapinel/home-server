# Home Server

A self-hosted application stack running locally and on AWS EC2, accessible remotely via WireGuard VPN.

## Services

| Service | URL | Description |
|---|---|---|
| Caddy | — | Reverse proxy, TLS termination |
| Grav | `pages.lapinel-fam.club` | CMS / static pages |
| Vikunja | `tasks.lapinel-fam.club` | Task management |
| Donetick | `chores.lapinel-fam.club` | Chore tracking |
| Actual Budget | `budget.lapinel-fam.club` | Personal finance |
| wg-easy | `wg.lapinel-fam.club` | WireGuard VPN management |
| Home Assistant | `ha.lapinel-home.arpa` | Home automation (local only) |
| AdGuard Home | — | DNS / ad blocking (local only) |

---

## Architecture

### Remote deployment (AWS EC2)

```
Client (WireGuard) ──────────────────────────────────────────►  EC2 (t3.small, us-east-2)
                        UDP 51820 only (Security Group)
                                                                  ┌─────────────────────┐
                                                                  │ wg-easy (host mode) │
                                                                  │  wg0 = 10.8.0.1     │
                                                                  └────────┬────────────┘
                                                                           │ Docker port mapping
                                                                  ┌────────▼────────────┐
                                                                  │       Caddy         │
                                                                  │  *.lapinel-fam.club │
                                                                  └────────┬────────────┘
                                                                           │ reverse proxy
                                                          ┌────────────────┼──────────────┐
                                                     vikunja         donetick        actual_server ...
```

**Key design decisions:**

- **VPN-only access** — security group only opens UDP 51820 (WireGuard). No 80/443 exposed to the internet.
- **Split tunnel** — client `AllowedIPs = 10.8.0.0/24`. Only traffic to the VPN subnet goes through the tunnel; normal internet traffic is unaffected.
- **DNS points to VPN IP** — `*.lapinel-fam.club` A records resolve to `10.8.0.1`. Records are public but useless without VPN.
- **wg-easy runs in host network mode** — so the `wg0` interface lives on the EC2 host. Docker's port mapping then forwards traffic from the VPN interface to the Caddy container.
- **TLS via Let's Encrypt DNS challenge** — Caddy uses a custom-built image with the `caddy-dns/route53` plugin. Real certs without opening port 80/443.
- **No SSH** — instance access via AWS SSM Session Manager only.
- **Secrets via SSM Parameter Store** — `.env` stored as a SecureString at `/home-server/.env`, fetched on boot.

---

## Prerequisites

- AWS CLI configured with SSO
- AWS CDK (`npm install -g aws-cdk`)
- Docker + Docker Compose (local)
- A WireGuard client

---

## Local setup

```bash
cp env/.env.example .env
# fill in .env
docker compose up -d
```

Local services use `*.lapinel-home.arpa` hostnames resolved by AdGuard Home.

---

## Remote setup (first time)

### 1. Seed secrets to SSM

Edit `.env.remote` with real values, then:

```bash
./update-remote.sh
```

> **Note:** bcrypt hashes in `WG_PASSWORD_HASH` must have `$` escaped as `$$` in `.env.remote` to prevent Docker Compose from interpreting them as variable references.

### 2. Deploy infrastructure

```bash
cd infra/cdk
npm ci
npx cdk deploy
```

Note the `ElasticIp` output — this is your WireGuard endpoint (`WG_HOST`).

### 3. Wait for bootstrap

The EC2 instance bootstraps automatically via user data. Monitor progress:

```bash
aws ssm start-session --target <instance-id> --region us-east-2
tail -f /var/log/home-server-bootstrap.log
```

The custom Caddy build (`xcaddy`) takes a few minutes on t3.small.

### 4. Set up WireGuard client

Forward the wg-easy UI port via SSM:

```bash
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["51821"],"localPortNumber":["51821"]}' \
  --region us-east-2
```

Open `http://localhost:51821`, create a client, download the config, set `AllowedIPs = 10.8.0.0/24` (split tunnel), and connect.

---

## Redeployment

If the instance is replaced (e.g., after `cdk destroy && cdk deploy`):
1. Note the new Elastic IP from CDK outputs
2. Update `WG_HOST` in `.env.remote`
3. Run `./update-remote.sh`
4. Repeat WireGuard client setup with the new endpoint

---

## Backups

```bash
./backup.sh    # snapshot to S3 via restic
./restore.sh [latest|<snapshot-id>]
```

See `docs/restore.md` for full details.

---

## Secrets management

| What | Where |
|---|---|
| Runtime env | SSM Parameter Store: `/home-server/.env` |
| On instance | `/etc/home-server/.env` |
| Compose symlink | `/opt/home-server/.env -> /etc/home-server/.env` |
| Local dev | `.env` (gitignored) |

To update secrets on a running instance:

```bash
# locally
./update-remote.sh

# on the instance
./pull-remote-param.sh
docker compose -f docker-compose.yml -f docker-compose.remote.yml up -d
```
