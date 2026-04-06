# Remote Bootstrap Runbook

## Prereqs
- AWS account and profile (SSO or IAM user). Example profile: `AdministratorAccess-955852928464`.
- Region: `us-east-2`.
- CDK context set in `infra/cdk/cdk.json` (`account`, `region`, `backupBucketName`, `repoUrl`).

## 1) Configure AWS CLI (one-time)
- SSO: `aws configure sso` → use your Start URL and SSO region → choose account 955852928464 and AdministratorAccess → profile name, e.g., `home-server`.
- Or static keys: `aws configure` (set as default or export `AWS_PROFILE=<name>`).

## 2) Seed remote env in SSM
- Prepare `.env.remote` locally (never commit secrets).
- Upload:
```
AWS_PROFILE=<profile> aws ssm put-parameter \
  --region us-east-2 \
  --name /home-server/.env \
  --type SecureString --overwrite \
  --value "$(cat .env.remote)"
```

## 3) Bootstrap and deploy CDK (VPN-only)
```
cd infra/cdk
AWS_PROFILE=<profile> npx cdk context --clear
npm ci && npm run build
AWS_PROFILE=<profile> npx cdk bootstrap
AWS_PROFILE=<profile> npx cdk deploy
```
Outputs include `InstanceId`, `PublicIp`, and `SgId`.

## 4) Verify on instance
```
AWS_PROFILE=<profile> aws ssm start-session --region us-east-2 --target <InstanceId>
# On instance
sudo tail -n 200 /var/log/home-server-bootstrap.log
sudo docker compose -f /opt/home-server/docker-compose.yml \
  -f /opt/home-server/docker-compose.remote.yml \
  --env-file /etc/home-server/.env ps
```

## 5) Set up WireGuard (no public exposure)
- Port-forward wg-easy UI:
```
AWS_PROFILE=<profile> aws ssm start-session \
  --region us-east-2 --target <InstanceId> \
  --document-name AWS-StartPortForwardingSession \
  --parameters portNumber=['51821'],localPortNumber=['51821']
```
- Open `http://localhost:51821` → login → add client → scan QR or download config.
 - Set `WG_HOST` to the stack output `ElasticIp` (or a DNS name pointing to it) and recreate peers after changing it.

## 6) Smoke tests
- Caddy logs: `sudo docker compose -f /opt/home-server/docker-compose.yml -f /opt/home-server/docker-compose.remote.yml logs -f caddy`.
- App routes over VPN (internal TLS): `pages.lapinel-home.arpa`, `tasks.lapinel-home.arpa`, etc.

## 7) Backups
- First backup on instance: `cd /opt/home-server && ./backup.sh`.
- Verify snapshots: `restic snapshots` (env must include `RESTIC_*`).

## Troubleshooting
- Missing env: ensure `/etc/home-server/.env` exists (seed via SSM).
- wg-easy not reachable via port-forward: confirm container up (`docker ps`) and port 51821 listening (`ss -ltnp | grep 51821`).
- Bootstrap failures: check `/var/log/home-server-bootstrap.log` and rerun `cd /opt/home-server && docker compose ... up -d`.
